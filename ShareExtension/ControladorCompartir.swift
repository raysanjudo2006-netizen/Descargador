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
        abrirDescargador(Enlaces.enlaceProfundo(para: enlace))
        // Un instante para que iOS cambie a la app antes de cerrar la hoja.
        try? await Task.sleep(nanoseconds: 400_000_000)
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

    /// Las extensiones no tienen UIApplication.shared: se busca la aplicación en la cadena de
    /// respondedores. En iOS 18 solo funciona open(_:options:completionHandler:); en versiones
    /// anteriores se recurre también a openURL: si hiciera falta.
    private func abrirDescargador(_ enlace: URL) {
        var respondedor: UIResponder? = self
        while let actual = respondedor {
            if let aplicacion = actual as? UIApplication {
                aplicacion.open(enlace, options: [:]) { [weak self] abierta in
                    if !abierta { self?.abrirConSelectorAntiguo(enlace) }
                }
                return
            }
            respondedor = actual.next
        }
        abrirConSelectorAntiguo(enlace)
    }

    private func abrirConSelectorAntiguo(_ enlace: URL) {
        let selector = sel_registerName("openURL:")
        var respondedor: UIResponder? = self
        while let actual = respondedor {
            if actual.responds(to: selector) {
                actual.perform(selector, with: enlace)
                return
            }
            respondedor = actual.next
        }
    }
}
