import Foundation

enum ErrorCookies: LocalizedError, Equatable {
    case formatoNoValido
    case lectura(String)

    var errorDescription: String? {
        switch self {
        case .formatoNoValido:
            return "Ese archivo no es un cookies.txt (formato Netscape). Expórtalo de nuevo desde el navegador."
        case .lectura(let motivo):
            return "No se pudo leer el archivo: \(motivo)"
        }
    }
}

/// Cookies opcionales (cookies.txt) para videos que piden tu sesión: privados, con edad o
/// cuando YouTube pide "confirmar que no eres un robot". Se guardan solo dentro de la app
/// (Application Support) y nunca se escriben en el Registro.
enum Cookies {
    static var archivo: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cookies.txt")
    }

    static var importadas: Bool {
        FileManager.default.fileExists(atPath: archivo.path)
    }

    /// Cuenta las cookies válidas de un texto en formato Netscape (7 campos separados por
    /// tabuladores). Las líneas "#HttpOnly_…" también son cookies; el resto de "#" son comentarios.
    static func contar(_ texto: String) -> Int {
        texto.split(whereSeparator: \.isNewline).filter { linea in
            let cookie = linea.hasPrefix("#HttpOnly_") ? linea.dropFirst("#HttpOnly_".count) : linea[...]
            guard !cookie.hasPrefix("#"), !cookie.allSatisfy(\.isWhitespace) else { return false }
            return cookie.split(separator: "\t", omittingEmptySubsequences: false).count == 7
        }.count
    }

    /// Copia el cookies.txt elegido dentro de la app. Devuelve cuántas cookies tiene.
    @discardableResult
    static func importar(desde origen: URL, destino: URL = archivo) throws -> Int {
        // Los archivos elegidos con el selector necesitan permiso de acceso temporal.
        let acceso = origen.startAccessingSecurityScopedResource()
        defer { if acceso { origen.stopAccessingSecurityScopedResource() } }
        let texto: String
        do {
            texto = try String(contentsOf: origen, encoding: .utf8)
        } catch {
            throw ErrorCookies.lectura(error.localizedDescription)
        }
        let cantidad = contar(texto)
        guard cantidad > 0 else { throw ErrorCookies.formatoNoValido }
        try FileManager.default.createDirectory(at: destino.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texto.utf8).write(to: destino, options: [.atomic, .completeFileProtection])
        return cantidad
    }

    static func borrar(_ destino: URL = archivo) {
        try? FileManager.default.removeItem(at: destino)
    }
}
