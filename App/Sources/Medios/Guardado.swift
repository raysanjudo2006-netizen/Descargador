import Foundation
import Photos

/// Errores al guardar el resultado.
enum ErrorGuardado: LocalizedError {
    case sinPermisoFotos
    case fotos(String)

    var errorDescription: String? {
        switch self {
        case .sinPermisoFotos:
            return "Sin permiso para guardar en Fotos. Actívalo en Ajustes › Descargador › Fotos › Añadir solo fotos. El archivo sigue en el Historial y en Archivos."
        case .fotos(let motivo):
            return "Fotos no aceptó el video: \(motivo). El archivo sigue en Archivos."
        }
    }
}

/// Dónde acaban los archivos.
enum Guardado {
    /// Documents/Descargas: se ve en la app Archivos (En mi iPhone › Descargador › Descargas).
    static var carpetaDescargas: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Descargas", isDirectory: true)
    }

    /// Mueve el archivo final a la carpeta de descargas con el título como nombre.
    static func moverADescargas(_ archivo: URL, titulo: String, carpeta: URL = carpetaDescargas) throws -> URL {
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let destino = NombresArchivo.sinColision(NombresArchivo.seguro(titulo),
                                                 extension: archivo.pathExtension.isEmpty ? "mp4" : archivo.pathExtension,
                                                 en: carpeta)
        try FileManager.default.moveItem(at: archivo, to: destino)
        return destino
    }

    /// Guarda una copia del video en Fotos. Pide el permiso "solo añadir" la primera vez.
    static func guardarEnFotos(_ video: URL) async throws {
        let estado = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard estado == .authorized || estado == .limited else {
            throw ErrorGuardado.sinPermisoFotos
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let peticion = PHAssetCreationRequest.forAsset()
                peticion.addResource(with: .video, fileURL: video, options: nil)
            }
        } catch {
            throw ErrorGuardado.fotos(error.localizedDescription)
        }
    }
}
