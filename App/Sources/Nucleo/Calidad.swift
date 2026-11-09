import Foundation

/// Calidad que el usuario elige para descargar.
///
/// El `rawValue` es el que se usa en el esquema `descargador://download?url=…&calidad=720`
/// y en Atajos, así que no debe cambiar.
enum Calidad: String, CaseIterable, Codable, Identifiable {
    case mejor
    case p1080 = "1080"
    case p720 = "720"
    case p480 = "480"
    case p360 = "360"
    case audio

    var id: String { rawValue }

    /// Texto del botón.
    var titulo: String {
        switch self {
        case .mejor: return "Mejor"
        case .p1080: return "1080p"
        case .p720: return "720p"
        case .p480: return "480p"
        case .p360: return "360p"
        case .audio: return "Solo audio"
        }
    }

    /// Altura máxima del video; `nil` para "Mejor" (sin límite) y "Solo audio".
    var alturaMaxima: Int? {
        switch self {
        case .p1080: return 1080
        case .p720: return 720
        case .p480: return 480
        case .p360: return 360
        case .mejor, .audio: return nil
        }
    }
}
