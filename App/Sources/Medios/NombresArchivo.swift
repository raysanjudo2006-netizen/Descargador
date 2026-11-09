import Foundation

/// Nombres de archivo legibles y seguros a partir del título del video.
enum NombresArchivo {
    /// Caracteres que no pueden ir en un nombre de archivo (o molestan en Archivos).
    /// Solo controles C0/C1: `.controlCharacters` incluiría el ZWJ que une emojis (👨‍👩‍👧).
    private static let prohibidos = CharacterSet(charactersIn: "/\\:*?\"<>|")
        .union(CharacterSet(charactersIn: Unicode.Scalar(UInt8(0x00))...Unicode.Scalar(UInt8(0x1F))))
        .union(CharacterSet(charactersIn: Unicode.Scalar(UInt8(0x7F))...Unicode.Scalar(UInt8(0x9F))))

    /// Límite de bytes UTF-8 del nombre (iOS admite 255 por nombre; se deja margen).
    private static let maximoBytes = 200

    /// "Mi video: parte 1/2" → "Mi video- parte 1-2". Recorta a `maximo` caracteres.
    static func seguro(_ titulo: String, maximo: Int = 80) -> String {
        var limpio = titulo.unicodeScalars
            .map { escalar -> String in
                // Saltos de línea y tabuladores cuentan como espacio (antes que "prohibidos").
                if CharacterSet.whitespacesAndNewlines.contains(escalar) { return " " }
                return prohibidos.contains(escalar) ? "-" : String(escalar)
            }
            .joined()
        // Espacios repetidos fuera; sin puntos al principio (serían archivos ocultos).
        limpio = limpio.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        while limpio.hasPrefix(".") { limpio.removeFirst() }
        limpio = String(limpio.prefix(maximo))
        // Un emoji puede ocupar hasta 25 bytes: se recorta también por bytes.
        while limpio.utf8.count > maximoBytes { limpio.removeLast() }
        limpio = limpio.trimmingCharacters(in: .whitespaces)
        return limpio.isEmpty ? "video" : limpio
    }

    /// Ruta libre en `carpeta`: "Título.mp4", y si existe "Título (2).mp4", "Título (3).mp4"…
    static func sinColision(_ nombre: String, extension ext: String, en carpeta: URL) -> URL {
        let gestor = FileManager.default
        var candidato = carpeta.appendingPathComponent(nombre).appendingPathExtension(ext)
        var numero = 2
        while gestor.fileExists(atPath: candidato.path) {
            candidato = carpeta.appendingPathComponent("\(nombre) (\(numero))").appendingPathExtension(ext)
            numero += 1
        }
        return candidato
    }
}
