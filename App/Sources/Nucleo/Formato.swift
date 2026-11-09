import Foundation

/// Textos de tamaños, velocidades y tiempos para la interfaz.
enum Formato {
    /// "12,3 MB" (según el idioma del iPhone).
    static func bytes(_ valor: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: valor, countStyle: .file)
    }

    /// "1,2 MB/s".
    static func velocidad(_ bytesPorSegundo: Double) -> String {
        "\(bytes(Int64(bytesPorSegundo)))/s"
    }

    /// "3:45" o "1:02:03".
    static func tiempo(_ segundos: Double) -> String {
        let total = max(0, Int(segundos.rounded()))
        let horas = total / 3600, minutos = (total % 3600) / 60, resto = total % 60
        return horas > 0
            ? String(format: "%d:%02d:%02d", horas, minutos, resto)
            : String(format: "%d:%02d", minutos, resto)
    }

    /// "45 %".
    static func porcentaje(_ fraccion: Double) -> String {
        "\(Int((min(1, max(0, fraccion)) * 100).rounded(.down))) %"
    }
}
