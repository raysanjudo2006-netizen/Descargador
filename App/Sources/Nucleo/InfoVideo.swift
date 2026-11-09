import Foundation

/// Resultado de analizar un enlace (lo devuelve descargador.puente.info).
struct InfoVideo: Decodable, Equatable {
    let id: String?
    let titulo: String
    let autor: String?
    let duracion: Double?
    let miniatura: String?
    let extractor: String?
    let urlPagina: String?
    let opciones: [OpcionCalidad]
    let avisos: [String]

    var urlMiniatura: URL? { miniatura.flatMap(URL.init(string:)) }

    /// "3:45" o "1:02:03".
    var duracionTexto: String? {
        guard let duracion, duracion > 0 else { return nil }
        return Formato.tiempo(duracion)
    }

    func opcion(_ calidad: Calidad) -> OpcionCalidad? {
        opciones.first { $0.calidad == calidad.rawValue }
    }
}

/// Qué se descargaría para una calidad (ver descargador/seleccion.py).
struct OpcionCalidad: Decodable, Equatable, Identifiable {
    let calidad: String
    let disponible: Bool
    /// Lado corto del video en píxeles (1080 = 1080p).
    let resolucion: Int?
    let video: String?
    let audio: String?
    /// Video y audio vienen separados y hay que unirlos (Etapa 3).
    let unir: Bool
    let bytes: Int64?
    let aproximado: Bool
    let protocolo: String?
    /// "Solo audio" sin pista suelta: se extrae del video.
    let extraerAudio: Bool

    var id: String { calidad }
    var tipo: Calidad? { Calidad(rawValue: calidad) }

    /// "12,3 MB" o "≈ 12,3 MB"; nil si no se conoce.
    var tamanoTexto: String? {
        guard let bytes else { return nil }
        let texto = Formato.bytes(bytes)
        return aproximado ? "≈ \(texto)" : texto
    }
}

/// Versiones del motor, para Ajustes.
struct VersionesMotor: Decodable, Equatable {
    let python: String
    let ytDlp: String
    let ytDlpEjs: String?
}
