import AVFoundation
import Foundation
import UIKit

/// Una descarga terminada.
struct EntradaHistorial: Codable, Identifiable, Equatable {
    let id: UUID
    let titulo: String
    let plataforma: Plataforma
    /// Nombre del archivo dentro de Documents/Descargas (no una ruta absoluta: la carpeta de la
    /// app cambia de ruta al reinstalarla).
    let nombreArchivo: String
    /// Nombre de la miniatura dentro de la carpeta de miniaturas (nil para audio).
    let nombreMiniatura: String?
    let bytes: Int64
    let fecha: Date
    let esAudio: Bool
    let calidad: String?
    let enlace: String
}

/// Envoltorio para leer el historial entrada a entrada sin fallar por una dañada.
private struct EntradaTolerante: Decodable {
    let entrada: EntradaHistorial?

    init(from decoder: Decoder) throws {
        entrada = try? EntradaHistorial(from: decoder)
    }
}

/// Historial de descargas (Application Support/historial.json), de la más nueva a la más vieja.
@MainActor
final class HistorialStore: ObservableObject {
    @Published private(set) var entradas: [EntradaHistorial] = []

    private let archivo: URL
    private let carpetaArchivos: URL
    private let carpetaMiniaturas: URL

    nonisolated static var carpetaSoporte: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }

    init(archivo: URL = HistorialStore.carpetaSoporte.appendingPathComponent("historial.json"),
         carpetaArchivos: URL = Guardado.carpetaDescargas,
         carpetaMiniaturas: URL = HistorialStore.carpetaSoporte.appendingPathComponent("Miniaturas", isDirectory: true)) {
        self.archivo = archivo
        self.carpetaArchivos = carpetaArchivos
        self.carpetaMiniaturas = carpetaMiniaturas
        if let datos = try? Data(contentsOf: archivo) {
            if let tolerantes = try? Self.decodificador.decode([EntradaTolerante].self, from: datos) {
                // Una entrada dañada no se lleva por delante a las demás.
                entradas = tolerantes.compactMap(\.entrada)
            } else {
                // Archivo ilegible: se aparta (no se sobrescribe) y se empieza de cero.
                let copia = archivo.deletingPathExtension()
                    .appendingPathExtension("danado-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.moveItem(at: archivo, to: copia)
            }
        }
    }

    // MARK: - Consultas

    func urlArchivo(_ entrada: EntradaHistorial) -> URL {
        carpetaArchivos.appendingPathComponent(entrada.nombreArchivo)
    }

    func urlMiniatura(_ entrada: EntradaHistorial) -> URL? {
        entrada.nombreMiniatura.map { carpetaMiniaturas.appendingPathComponent($0) }
    }

    /// El archivo sigue ahí (el usuario puede haberlo borrado desde Archivos).
    func existeArchivo(_ entrada: EntradaHistorial) -> Bool {
        FileManager.default.fileExists(atPath: urlArchivo(entrada).path)
    }

    // MARK: - Cambios

    /// Añade una descarga terminada (con miniatura generada del propio video, sin red).
    func agregar(_ resultado: ResultadoFinal, plataforma: Plataforma, calidad: Calidad?, enlace: URL) async {
        let id = UUID()
        var nombreMiniatura: String?
        if !resultado.esAudio {
            try? FileManager.default.createDirectory(at: carpetaMiniaturas, withIntermediateDirectories: true)
            let nombre = "\(id.uuidString).jpg"
            if await Self.generarMiniatura(de: resultado.archivo, en: carpetaMiniaturas.appendingPathComponent(nombre)) {
                nombreMiniatura = nombre
            }
        }
        let bytes = (try? resultado.archivo.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        let entrada = EntradaHistorial(id: id, titulo: resultado.titulo, plataforma: plataforma,
                                       nombreArchivo: resultado.archivo.lastPathComponent,
                                       nombreMiniatura: nombreMiniatura, bytes: bytes, fecha: Date(),
                                       esAudio: resultado.esAudio, calidad: calidad?.rawValue,
                                       enlace: enlace.absoluteString)
        // Si una entrada vieja apuntaba a un archivo ya borrado con el mismo nombre, ese nombre
        // ahora es de esta descarga: la vieja se quita para que nunca abra ni borre la nueva.
        entradas.removeAll { $0.nombreArchivo == entrada.nombreArchivo }
        entradas.insert(entrada, at: 0)
        guardar()
    }

    /// Borra la entrada y su archivo de la app (la copia de Fotos no se toca).
    func borrar(_ entrada: EntradaHistorial) {
        try? FileManager.default.removeItem(at: urlArchivo(entrada))
        if let miniatura = urlMiniatura(entrada) {
            try? FileManager.default.removeItem(at: miniatura)
        }
        entradas.removeAll { $0.id == entrada.id }
        guardar()
    }

    /// Vacía el historial (los archivos los borra Guardado.vaciar()).
    func vaciar() {
        try? FileManager.default.removeItem(at: carpetaMiniaturas)
        entradas.removeAll()
        guardar()
    }

    // MARK: - Interno

    private func guardar() {
        try? FileManager.default.createDirectory(at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let datos = try? Self.codificador.encode(entradas) {
            try? datos.write(to: archivo, options: .atomic)
        }
    }

    private static let codificador: JSONEncoder = {
        let codificador = JSONEncoder()
        codificador.dateEncodingStrategy = .iso8601
        return codificador
    }()

    private static let decodificador: JSONDecoder = {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .iso8601
        return decodificador
    }()

    /// Fotograma del segundo 1 como JPEG de 320 px como máximo.
    nonisolated static func generarMiniatura(de video: URL, en destino: URL) async -> Bool {
        let generador = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generador.appliesPreferredTrackTransform = true
        generador.maximumSize = CGSize(width: 320, height: 320)
        do {
            let (imagen, _) = try await generador.image(at: CMTime(seconds: 1, preferredTimescale: 600))
            guard let datos = UIImage(cgImage: imagen).jpegData(compressionQuality: 0.7) else { return false }
            try datos.write(to: destino, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
