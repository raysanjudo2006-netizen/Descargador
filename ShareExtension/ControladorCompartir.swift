import UIKit
import UniformTypeIdentifiers

/// Extensión de Compartir: aparece como "Descargador" en la hoja de Compartir de YouTube,
/// TikTok, Instagram, X, Safari… Toma el enlace (o el texto que lo contiene) y abre la app con
/// descargador://download?url=…, que ya sabe analizarlo y descargarlo.
///
/// No usa App Groups (no disponibles de forma fiable con cuenta gratuita): solo pasa el enlace.
final class ControladorCompartir: UIViewController {
    private let etiqueta = UILabel()
    private let indicador = UIActivityIndicatorView(style: .medium)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        etiqueta.text = "Abriendo Descargador…"
        etiqueta.font = .preferredFont(forTextStyle: .headline)
        etiqueta.adjustsFontForContentSizeCategory = true
        etiqueta.textAlignment = .center
        etiqueta.numberOfLines = 0
        indicador.startAnimating()

        let pila = UIStackView(arrangedSubviews: [indicador, etiqueta])
        pila.axis = .vertical
        pila.spacing = 12
        pila.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(pila)
        NSLayoutConstraint.activate([
            pila.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            pila.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            pila.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
            pila.trailingAnchor.constraint(lessThanOrEqualTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        Task { await procesar() }
    }

    @MainActor
    private func procesar() async {
        guard let enlace = await buscarEnlace() else {
            indicador.stopAnimating()
            etiqueta.text = "No encontré un enlace en lo que compartiste."
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            extensionContext?.completeRequest(returningItems: nil)
            return
        }
        // El enlace web (no el descargador://): es lo que el aviso del portapapeles de la app reconoce.
        UIPasteboard.general.string = enlace.absoluteString
        abrirDescargador(Enlaces.enlaceProfundo(para: enlace))
        etiqueta.text = "Abriendo Descargador…\nSi no se abre, ábrelo tú: el enlace ya está copiado."
        // Un instante para que iOS cambie a la app antes de cerrar la hoja.
        try? await Task.sleep(nanoseconds: 700_000_000)
        extensionContext?.completeRequest(returningItems: nil)
    }

    /// Primer enlace web entre lo compartido: una URL o un texto que la contenga.
    private func buscarEnlace() async -> URL? {
        let elementos = (extensionContext?.inputItems as? [NSExtensionItem]) ?? []
        for elemento in elementos {
            for proveedor in elemento.attachments ?? [] {
                if proveedor.hasItemConformingToTypeIdentifier(UTType.url.identifier),
                   let datos = try? await proveedor.loadItem(forTypeIdentifier: UTType.url.identifier),
                   let enlace = enlace(en: datos) {
                    return enlace
                }
                if proveedor.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let datos = try? await proveedor.loadItem(forTypeIdentifier: UTType.plainText.identifier),
                   let enlace = enlace(en: datos) {
                    return enlace
                }
            }
            if let texto = elemento.attributedContentText?.string, let enlace = Enlaces.extraerPrimerEnlace(de: texto) {
                return enlace
            }
        }
        return nil
    }

    /// Las apps entregan el contenido como URL, texto o datos según cada una.
    private func enlace(en datos: NSSecureCoding) -> URL? {
        if let url = datos as? URL {
            return Enlaces.esWeb(url) ? url : nil
        }
        if let texto = datos as? String {
            return Enlaces.extraerPrimerEnlace(de: texto)
        }
        if let bytes = datos as? Data, let texto = String(data: bytes, encoding: .utf8) {
            return Enlaces.extraerPrimerEnlace(de: texto)
        }
        return nil
    }

    /// Las extensiones no pueden llamar a UIApplication.open (Xcode exige compilarlas solo con
    /// API de extensiones). Se busca en la cadena de respondedores a la aplicación y se le llama
    /// a través del runtime de Objective-C:
    /// - iOS 18+: openURL:options:completionHandler: (openURL: ya no hace nada).
    /// - iOS 17 y anteriores: openURL:. El método nuevo existe pero no abre nada desde una
    ///   extensión, así que hay que usar el antiguo primero (era el fallo en iOS 17).
    /// Además el enlace queda copiado: si iOS no abre la app, al abrirla a mano lo ofrece.
    private func abrirDescargador(_ enlace: URL) {
        if #available(iOS 18.0, *) {
            if abrirConSelectorNuevo(enlace) { return }
            _ = abrirConSelectorAntiguo(enlace)
        } else {
            if abrirConSelectorAntiguo(enlace) { return }
            _ = abrirConSelectorNuevo(enlace)
        }
    }

    @discardableResult
    private func abrirConSelectorNuevo(_ enlace: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var respondedor: UIResponder? = self
        while let actual = respondedor {
            if actual.responds(to: selector), let implementacion = actual.method(for: selector) {
                typealias Abrir = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let abrir = unsafeBitCast(implementacion, to: Abrir.self)
                abrir(actual, selector, enlace as NSURL, NSDictionary(), nil)
                return true
            }
            respondedor = actual.next
        }
        return false
    }

    /// true si iOS aceptó abrir el enlace (openURL: devuelve un BOOL).
    @discardableResult
    private func abrirConSelectorAntiguo(_ enlace: URL) -> Bool {
        let selector = sel_registerName("openURL:")
        var respondedor: UIResponder? = self
        while let actual = respondedor {
            if actual.responds(to: selector), let implementacion = actual.method(for: selector) {
                typealias Abrir = @convention(c) (AnyObject, Selector, NSURL) -> Bool
                let abrir = unsafeBitCast(implementacion, to: Abrir.self)
                return abrir(actual, selector, enlace as NSURL)
            }
            respondedor = actual.next
        }
        return false
    }
}
