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
    /// Duración final: la más corta de las pistas y, si se conoce, nunca más de lo que dura el
    /// video en la plataforma (+1 s de margen).
    ///
    /// YouTube entrega a veces el video sin audio con una cabecera que dice el DOBLE de lo que
    /// dura: usar esa cifra dejaba archivos del doble de largo (la segunda mitad congelada).
    static func duracionFinal(_ pistas: [CMTime], esperada: Double?) -> CMTime {
        let validas = pistas.filter { $0.isValid && $0.seconds > 0 }
        guard var duracion = validas.first else { return .zero }
        for pista in validas.dropFirst() {
            duracion = CMTimeMinimum(duracion, pista)
        }
        if let esperada, esperada > 0 {
            duracion = CMTimeMinimum(duracion, CMTime(seconds: esperada + 1, preferredTimescale: 600))
        }
        return duracion
    }

    /// Une un video (sin audio) y un audio en un MP4, con la duración real del video
    /// (ver `duracionFinal`). `duracionEsperada`: la que dio yt-dlp al analizar.
    static func unir(video: URL, audio: URL, destino: URL, duracionEsperada: Double? = nil,
                     progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let activoVideo = AVURLAsset(url: video)
        let activoAudio = AVURLAsset(url: audio)
        guard let pistaVideo = try await activoVideo.loadTracks(withMediaType: .video).first else {
            throw ErrorMedios.sinPistaDeVideo
        }
        guard let pistaAudio = try await activoAudio.loadTracks(withMediaType: .audio).first else {
            throw ErrorMedios.sinPistaDeAudio
        }
        // El tramo de cada pista (lo que de verdad tiene), no la duración de la cabecera.
        let tramoVideo = try await pistaVideo.load(.timeRange)
        let tramoAudio = try await pistaAudio.load(.timeRange)
        let duracion = duracionFinal([tramoVideo.duration, tramoAudio.duration], esperada: duracionEsperada)

        let composicion = AVMutableComposition()
        guard let video = composicion.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let audio = composicion.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw ErrorMedios.exportacion("no se pudo crear la composición")
        }
        try video.insertTimeRange(CMTimeRange(start: tramoVideo.start, duration: duracion), of: pistaVideo, at: .zero)
        video.preferredTransform = try await pistaVideo.load(.preferredTransform)
        try audio.insertTimeRange(CMTimeRange(start: tramoAudio.start, duration: duracion), of: pistaAudio, at: .zero)

        try await exportar(composicion, preset: AVAssetExportPresetPassthrough, tipo: .mp4,
                           destino: destino, progreso: progreso)
    }

    /// Reempaqueta un video ya completo (con su audio) en un MP4 normal que Fotos acepta
    /// (p. ej. un MP4 fragmentado de DASH). Sin recodificar.
    /// Si el archivo dice durar más de lo real (ver `duracionFinal`), se recorta.
    static func prepararVideo(_ origen: URL, destino: URL, duracionEsperada: Double? = nil,
                              progreso: @escaping (Double) -> Void = { _ in }) async throws {
        let activo = AVURLAsset(url: origen)
        let pistasVideo = try await activo.loadTracks(withMediaType: .video)
        guard !pistasVideo.isEmpty else {
            throw ErrorMedios.formatoNoCompatible
        }
        let pistasAudio = try await activo.loadTracks(withMediaType: .audio)
        var tramos: [CMTime] = []
        for pista in pistasVideo + pistasAudio {
            tramos.append(try await pista.load(.timeRange).duration)
        }
        let duracion = duracionFinal(tramos, esperada: duracionEsperada)
        let total = try await activo.load(.duration)
        let recortar = CMTimeCompare(duracion, .zero) > 0 && CMTimeCompare(duracion, total) < 0
        let recorte = recortar ? CMTimeRange(start: .zero, duration: duracion) : nil
        try await exportar(activo, preset: AVAssetExportPresetPassthrough, tipo: .mp4,
                           destino: destino, tramo: recorte, progreso: progreso)
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
                                 tramo: CMTimeRange? = nil,
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
        if let tramo {
            sesion.timeRange = tramo
        }

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
        // Parar el vigilante antes de dar el resultado: así nunca llega un progreso viejo tras el 1.
        vigilante.cancel()
        _ = await vigilante.value

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
