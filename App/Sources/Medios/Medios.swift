import AVFoundation
import Foundation

/// Errores al procesar audio y video.
enum ErrorMedios: LocalizedError, Equatable {
    case sinPistaDeVideo
    case sinPistaDeAudio
    case formatoNoCompatible
    case exportacion(String)

    var errorDescription: String? {
        switch self {
        case .sinPistaDeVideo: return "El archivo descargado no tiene video."
        case .sinPistaDeAudio: return "El archivo descargado no tiene audio."
        case .formatoNoCompatible: return "Este formato no lo puede abrir el iPhone. Prueba otra calidad."
        case .exportacion(let motivo): return "No se pudo preparar el archivo: \(motivo)"
        }
    }
}

/// Unión y conversión de medios con AVFoundation, siempre sin recodificar el video
/// (passthrough): es rápido y no pierde calidad. No se usa ffmpeg.
enum Medios {
    /// Une un video (sin audio) y un audio en un MP4. Si el audio es más largo, se recorta.
    static func unir(video: URL, audio: URL, destino: URL,
                     progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let activoVideo = AVURLAsset(url: video)
        let activoAudio = AVURLAsset(url: audio)
        guard let pistaVideo = try await activoVideo.loadTracks(withMediaType: .video).first else {
            throw ErrorMedios.sinPistaDeVideo
        }
        guard let pistaAudio = try await activoAudio.loadTracks(withMediaType: .audio).first else {
            throw ErrorMedios.sinPistaDeAudio
        }
        let duracionVideo = try await activoVideo.load(.duration)
        let duracionAudio = try await activoAudio.load(.duration)

        let composicion = AVMutableComposition()
        guard let video = composicion.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composicion.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw ErrorMedios.exportacion("no se pudo crear la composición")
        }
        try video.insertTimeRange(CMTimeRange(start: .zero, duration: duracionVideo), of: pistaVideo, at: .zero)
        video.preferredTransform = try await pistaVideo.load(.preferredTransform)
        let duracion = CMTimeMinimum(duracionVideo, duracionAudio)
        try audio.insertTimeRange(CMTimeRange(start: .zero, duration: duracion), of: pistaAudio, at: .zero)

        try await exportar(composicion, preset: AVAssetExportPresetPassthrough, tipo: .mp4,
                           destino: destino, progreso: progreso)
    }

    /// Reempaqueta un video ya completo (con su audio) en un MP4 normal que Fotos acepta
    /// (p. ej. un MP4 fragmentado de DASH). Sin recodificar.
    static func prepararVideo(_ origen: URL, destino: URL,
                              progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let activo = AVURLAsset(url: origen)
        guard try await !activo.loadTracks(withMediaType: .video).isEmpty else {
            throw ErrorMedios.formatoNoCompatible
        }
        try await exportar(activo, preset: AVAssetExportPresetPassthrough, tipo: .mp4,
                           destino: destino, progreso: progreso)
    }

    /// Extrae la pista de audio de un video a M4A (AAC).
    static func extraerAudio(de video: URL, destino: URL,
                             progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let activo = AVURLAsset(url: video)
        guard try await !activo.loadTracks(withMediaType: .audio).isEmpty else {
            throw ErrorMedios.sinPistaDeAudio
        }
        try await exportar(activo, preset: AVAssetExportPresetAppleM4A, tipo: .m4a,
                           destino: destino, progreso: progreso)
    }

    /// Reempaqueta un audio descargado (p. ej. M4A de DASH) en un M4A normal.
    /// Si no se puede sin recodificar, lo convierte a AAC.
    static func normalizarAudio(_ origen: URL, destino: URL) async throws {
        let activo = AVURLAsset(url: origen)
        guard try await !activo.loadTracks(withMediaType: .audio).isEmpty else {
            throw ErrorMedios.sinPistaDeAudio
        }
        do {
            try await exportar(activo, preset: AVAssetExportPresetPassthrough, tipo: .m4a, destino: destino)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try await exportar(activo, preset: AVAssetExportPresetAppleM4A, tipo: .m4a, destino: destino)
        }
    }

    // MARK: - Exportación

    private static func exportar(_ activo: AVAsset, preset: String, tipo: AVFileType, destino: URL,
                                 progreso: @escaping (Double) -> Void = { _ in }) async throws {
        try? FileManager.default.removeItem(at: destino)
        guard let sesion = AVAssetExportSession(asset: activo, presetName: preset) else {
            throw ErrorMedios.formatoNoCompatible
        }
        guard sesion.supportedFileTypes.contains(tipo) else {
            throw ErrorMedios.formatoNoCompatible
        }
        sesion.outputURL = destino
        sesion.outputFileType = tipo
        sesion.shouldOptimizeForNetworkUse = true

        // Progreso cada 0,2 s mientras exporta.
        let vigilante = Task {
            while !Task.isCancelled {
                progreso(Double(sesion.progress))
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
        defer { vigilante.cancel() }

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuacion: CheckedContinuation<Void, Never>) in
                sesion.exportAsynchronously { continuacion.resume() }
            }
        } onCancel: {
            sesion.cancelExport()
        }

        switch sesion.status {
        case .completed:
            progreso(1)
        case .cancelled:
            throw CancellationError()
        default:
            throw ErrorMedios.exportacion(sesion.error?.localizedDescription ?? "error desconocido")
        }
    }
}
