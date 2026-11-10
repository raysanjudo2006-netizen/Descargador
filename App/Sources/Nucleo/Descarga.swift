import Foundation

/// Una parte que descarga yt-dlp: "video" o "audio" con su format_id.
struct ParteDescarga: Equatable {
    let parte: String
    let formato: String
}

/// Progreso de una parte, tal como lo manda Python.
struct ProgresoParte: Equatable {
    let parte: String
    let terminado: Bool
    let descargado: Int64
    let total: Int64?
    let estimado: Bool
    /// Bytes por segundo.
    let velocidad: Double?
    /// Segundos restantes de esta parte.
    let eta: Double?
}

/// Respuesta de descargador.puente.descargar.
struct ResultadoDescargaPython: Decodable, Equatable {
    let archivos: [String: String]
    let titulo: String?
    let id: String?
}

/// Respuesta de descargador.puente.probar_js.
struct PruebaJavaScript: Decodable, Equatable {
    let salida: String
    let segundos: Double
}

/// Respuesta de descargador.puente.inspeccionar_paquete.
struct PaqueteYtDlp: Decodable, Equatable {
    let ytDlp: String
    let ejs: String?
    let incluyeEjs: Bool
}

/// Lo que necesita GestorDescargas del motor (MotorPython en la app; uno falso en los tests).
protocol MotorDescargas {
    func descargar(url: URL, partes: [ParteDescarga], carpeta: URL, permitirArchivos: Bool,
                   alProgreso: @escaping (ProgresoParte) -> Void,
                   cancelado: @escaping () -> Bool) async throws -> ResultadoDescargaPython
}

extension MotorPython: MotorDescargas {}

/// Progreso total que se muestra (suma de video y audio).
struct ProgresoTotal: Equatable {
    var descargado: Int64 = 0
    /// nil si no se conoce el tamaño.
    var total: Int64?
    var aproximado = false
    var velocidad: Double?
    /// Segundos restantes.
    var eta: Double?
    /// Parte que se está descargando y su posición ("video", 1 de 2).
    var parte: String?
    var numeroParte = 1
    var partes = 1

    /// 0…1, o nil si no se conoce el total.
    var fraccion: Double? {
        guard let total, total > 0 else { return nil }
        return min(1, max(0, Double(descargado) / Double(total)))
    }
}

/// Junta el progreso de las partes en un único progreso total.
struct AcumuladorProgreso: Equatable {
    let partes: [String]
    /// Tamaño total que calculó el análisis (puede ser aproximado o nil).
    let estimacionTotal: Int64?

    private var descargadoPorParte: [String: Int64] = [:]
    private var totalPorParte: [String: Int64] = [:]
    private var estimadoPorParte: [String: Bool] = [:]
    private var ultimo: ProgresoParte?

    init(partes: [String], estimacionTotal: Int64?) {
        self.partes = partes
        self.estimacionTotal = estimacionTotal
    }

    mutating func actualizar(_ progreso: ProgresoParte) {
        descargadoPorParte[progreso.parte] = progreso.descargado
        if let total = progreso.total {
            totalPorParte[progreso.parte] = total
            estimadoPorParte[progreso.parte] = progreso.estimado
        } else if progreso.terminado {
            // Al terminar, lo descargado es el tamaño real de la parte.
            totalPorParte[progreso.parte] = progreso.descargado
            estimadoPorParte[progreso.parte] = false
        }
        ultimo = progreso
    }

    var resumen: ProgresoTotal {
        var resultado = ProgresoTotal()
        resultado.descargado = descargadoPorParte.values.reduce(0, +)
        resultado.partes = max(1, partes.count)
        if let parte = ultimo?.parte {
            resultado.parte = parte
            resultado.numeroParte = (partes.firstIndex(of: parte) ?? 0) + 1
        }

        if partes.allSatisfy({ totalPorParte[$0] != nil }) {
            resultado.total = partes.compactMap { totalPorParte[$0] }.reduce(0, +)
            resultado.aproximado = partes.contains { estimadoPorParte[$0] ?? false }
        } else if let estimacionTotal {
            // Falta el tamaño de alguna parte: se usa el del análisis (nunca menor que lo ya bajado).
            resultado.total = max(estimacionTotal, resultado.descargado)
            resultado.aproximado = true
        }

        resultado.velocidad = ultimo?.velocidad
        if let total = resultado.total, let velocidad = resultado.velocidad, velocidad > 0 {
            resultado.eta = Double(max(0, total - resultado.descargado)) / velocidad
        } else {
            resultado.eta = ultimo?.eta
        }
        return resultado
    }
}

/// Resultado de una descarga terminada.
struct ResultadoFinal: Equatable {
    let archivo: URL
    let titulo: String
    let esAudio: Bool
    let enFotos: Bool
    /// Motivo si no se pudo guardar en Fotos (el archivo sigue en Archivos).
    let avisoFotos: String?
}

/// En qué punto está la descarga actual.
enum FaseDescarga: Equatable {
    case inactiva
    case preparando
    case descargando(ProgresoTotal)
    /// Paso posterior a la descarga ("Uniendo audio y video") con su progreso 0…1.
    case procesando(String, Double)
    case terminada(ResultadoFinal)
    case fallida(String)
    case cancelada
}
