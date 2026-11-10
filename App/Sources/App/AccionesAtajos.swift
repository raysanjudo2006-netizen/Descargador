import AppIntents
import Foundation

/// Calidad tal como aparece en la app Atajos.
enum CalidadAtajo: String, AppEnum {
    case mejor, p1080, p720, p480, p360, audio

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Calidad"
    static var caseDisplayRepresentations: [CalidadAtajo: DisplayRepresentation] = [
        .mejor: "Mejor",
        .p1080: "1080p",
        .p720: "720p",
        .p480: "480p",
        .p360: "360p",
        .audio: "Solo audio",
    ]

    var calidad: Calidad {
        switch self {
        case .mejor: return .mejor
        case .p1080: return .p1080
        case .p720: return .p720
        case .p480: return .p480
        case .p360: return .p360
        case .audio: return .audio
        }
    }
}

/// Acción "Descargar video" para la app Atajos: abre Descargador, analiza el enlace y descarga
/// en la calidad elegida. Funciona con cuenta gratuita (no necesita ningún permiso especial).
struct DescargarVideoIntent: AppIntent {
    static var title: LocalizedStringResource = "Descargar video"
    static var description = IntentDescription("Abre Descargador con el enlace y descarga el video en la calidad elegida.")
    /// La descarga necesita la app en primer plano (Python, progreso, Fotos).
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Enlace", description: "Enlace del video, o el texto compartido que lo contiene")
    var enlace: String

    @Parameter(title: "Calidad", default: .p720)
    var calidad: CalidadAtajo

    static var parameterSummary: some ParameterSummary {
        Summary("Descargar \(\.$enlace) en \(\.$calidad)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = Enlaces.extraerPrimerEnlace(de: enlace) else {
            throw $enlace.needsValueError("No encontré un enlace. ¿Qué video quieres descargar?")
        }
        BuzonEnlaces.compartido.depositar(Enlaces.enlaceProfundo(para: url, calidad: calidad.calidad))
        return .result()
    }
}

/// Atajo listo para usar (también con Siri: "Descargar video con Descargador").
struct AtajosDescargador: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: DescargarVideoIntent(), phrases: ["Descargar video con \(.applicationName)"])
    }
}
