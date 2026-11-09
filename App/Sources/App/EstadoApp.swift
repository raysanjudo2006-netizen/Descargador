import Foundation
import SwiftUI

/// Pestañas principales de la app.
enum Pestana: String, CaseIterable, Hashable {
    case descargar, historial, ajustes, registro
}

/// Tema elegido en Ajustes (se guarda con @AppStorage("apariencia")).
enum Apariencia: String, CaseIterable, Identifiable {
    case sistema, claro, oscuro

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .sistema: return "Automático"
        case .claro: return "Claro"
        case .oscuro: return "Oscuro"
        }
    }

    /// `nil` = seguir el ajuste del iPhone.
    var esquema: ColorScheme? {
        switch self {
        case .sistema: return nil
        case .claro: return .light
        case .oscuro: return .dark
        }
    }
}

/// Estado compartido por las pantallas: qué pestaña se ve y qué enlace se está analizando.
@MainActor
final class EstadoApp: ObservableObject {
    @Published var pestana: Pestana

    /// Texto del campo de enlace. Al editarlo se descarta el resultado anterior
    /// (y la calidad que viniera de Atajos: ya no corresponde a este enlace).
    @Published var textoEnlace: String = "" {
        didSet {
            guard textoEnlace != oldValue else { return }
            enlaceAnalizado = nil
            mensajeError = nil
            calidadSolicitada = nil
        }
    }

    /// Mensaje de error en español para mostrar bajo el campo.
    @Published var mensajeError: String?

    /// Calidad pedida desde fuera (Atajos o descargador://…&calidad=…).
    @Published var calidadSolicitada: Calidad?

    /// Último enlace válido analizado.
    @Published private(set) var enlaceAnalizado: URL?

    private let registro: Registro

    init(pestanaInicial: Pestana = .descargar, registro: Registro = .compartido) {
        self.pestana = pestanaInicial
        self.registro = registro
    }

    /// Valida el texto del campo y, si contiene un enlace, lo deja listo para analizar.
    /// (En la Etapa 2 aquí se llamará a yt-dlp.)
    func analizar() {
        let texto = textoEnlace.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !texto.isEmpty else {
            mensajeError = "Pega primero el enlace de un video."
            return
        }
        guard let url = Enlaces.extraerPrimerEnlace(de: texto) else {
            enlaceAnalizado = nil
            mensajeError = "Eso no parece un enlace. Copia el enlace del video y pégalo aquí."
            registro.aviso("Texto sin enlace válido: \"\(texto.prefix(80))\"", categoria: "ui")
            return
        }
        aceptar(url)
    }

    /// Usa lo que el usuario pegó: extrae el primer enlace (TikTok pega texto alrededor) y lo analiza.
    func usarTextoPegado(_ texto: String) {
        if let url = Enlaces.extraerPrimerEnlace(de: texto) {
            aceptar(url)
        } else {
            textoEnlace = texto.trimmingCharacters(in: .whitespacesAndNewlines)
            analizar()
        }
    }

    /// Deja un enlace ya validado como el actual, sin volver a pasarlo por el detector de enlaces.
    private func aceptar(_ url: URL) {
        textoEnlace = url.absoluteString
        mensajeError = nil
        enlaceAnalizado = url
        registro.info("Enlace listo (\(Plataforma.detectar(url).nombre)): \(url.absoluteString)", categoria: "ui")
    }

    /// Abre un enlace descargador://download?url=…[&calidad=…] (Share Extension, Atajos, Safari).
    func abrir(enlaceProfundo url: URL) {
        guard let peticion = Enlaces.peticion(desde: url) else {
            if (url.host ?? "").isEmpty {
                registro.info("App abierta con \(url.absoluteString)", categoria: "esquema")
            } else {
                registro.aviso("Enlace de la app no reconocido: \(url.absoluteString)", categoria: "esquema")
            }
            return
        }
        registro.info(
            "Recibido por descargador://: \(peticion.url.absoluteString) (calidad: \(peticion.calidad?.titulo ?? "sin indicar"))",
            categoria: "esquema")
        pestana = .descargar
        aceptar(peticion.url)
        // Después de aceptar: cambiar el texto borra la calidad anterior.
        calidadSolicitada = peticion.calidad
    }
}
