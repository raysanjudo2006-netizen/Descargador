import AVFoundation
import XCTest
@testable import Descargador

/// Genera medios reales y cortos para las pruebas (sin red).
enum GeneradorMedios {
    /// Video H.264 de 128×72 sin audio, a 10 fotogramas por segundo.
    static func video(segundos: Double, en url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let escritor = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let entrada = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 128,
            AVVideoHeightKey: 72,
        ])
        let adaptador = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: entrada, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 128,
            kCVPixelBufferHeightKey as String: 72,
        ])
        escritor.add(entrada)
        XCTAssertTrue(escritor.startWriting(), "\(String(describing: escritor.error))")
        escritor.startSession(atSourceTime: .zero)
        let fotogramas = Int(segundos * 10)
        for i in 0..<fotogramas {
            while !entrada.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            var buffer: CVPixelBuffer?
            guard let pool = adaptador.pixelBufferPool else { throw ErrorMedios.exportacion("sin pool de píxeles") }
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw ErrorMedios.exportacion("sin buffer de píxeles") }
            adaptador.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 10))
        }
        entrada.markAsFinished()
        await escritor.finishWriting()
        if escritor.status != .completed {
            throw ErrorMedios.exportacion("no se pudo generar el video: \(String(describing: escritor.error))")
        }
    }

    /// Audio AAC (silencio) en M4A.
    static func audio(segundos: Double, en url: URL) throws {
        try? FileManager.default.removeItem(at: url)
        let frecuencia = 44_100.0
        let archivo = try AVAudioFile(forWriting: url, settings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: frecuencia,
            AVNumberOfChannelsKey: 1,
        ])
        let muestras = AVAudioFrameCount(frecuencia * segundos)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: archivo.processingFormat, frameCapacity: muestras) else {
            throw ErrorMedios.exportacion("sin buffer de audio")
        }
        buffer.frameLength = muestras  // ceros = silencio
        try archivo.write(from: buffer)
    }
}

/// Unión y conversión con AVFoundation sobre archivos generados en el simulador.
final class MediosTests: XCTestCase {
    private var carpeta: URL!

    override func setUpWithError() throws {
        carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
    }

    private func pistas(_ url: URL, _ tipo: AVMediaType) async throws -> Int {
        try await AVURLAsset(url: url).loadTracks(withMediaType: tipo).count
    }

    private func duracion(_ url: URL) async throws -> Double {
        try await AVURLAsset(url: url).load(.duration).seconds
    }

    func test_unirVideoYAudio() async throws {
        let video = carpeta.appendingPathComponent("video.mp4")
        let audio = carpeta.appendingPathComponent("audio.m4a")
        let salida = carpeta.appendingPathComponent("final.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        try GeneradorMedios.audio(segundos: 1, en: audio)
        var ultimoProgreso = 0.0
        try await Medios.unir(video: video, audio: audio, destino: salida) { ultimoProgreso = $0 }
        let videos = try await pistas(salida, .video)
        let audios = try await pistas(salida, .audio)
        XCTAssertEqual(videos, 1)
        XCTAssertEqual(audios, 1)
        XCTAssertEqual(ultimoProgreso, 1)
    }

    func test_unirConAudioMasLargo() async throws {
        let video = carpeta.appendingPathComponent("video.mp4")
        let audio = carpeta.appendingPathComponent("audio.m4a")
        let salida = carpeta.appendingPathComponent("final.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        try GeneradorMedios.audio(segundos: 3, en: audio)
        try await Medios.unir(video: video, audio: audio, destino: salida)
        let segundos = try await duracion(salida)
        XCTAssertLessThan(segundos, 1.5, "El audio sobrante debe recortarse")
    }

    func test_unirSinAudioDaErrorClaro() async throws {
        let video = carpeta.appendingPathComponent("video.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        do {
            try await Medios.unir(video: video, audio: video, destino: carpeta.appendingPathComponent("x.mp4"))
            XCTFail("Debería fallar: el 'audio' no tiene pista de audio")
        } catch let error as ErrorMedios {
            XCTAssertEqual(error, .sinPistaDeAudio)
        }
    }

    func test_extraerAudioYPrepararVideo() async throws {
        let video = carpeta.appendingPathComponent("video.mp4")
        let audio = carpeta.appendingPathComponent("audio.m4a")
        let unido = carpeta.appendingPathComponent("unido.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        try GeneradorMedios.audio(segundos: 1, en: audio)
        try await Medios.unir(video: video, audio: audio, destino: unido)

        let soloAudio = carpeta.appendingPathComponent("solo.m4a")
        try await Medios.extraerAudio(de: unido, destino: soloAudio)
        let videosEnAudio = try await pistas(soloAudio, .video)
        let audiosEnAudio = try await pistas(soloAudio, .audio)
        XCTAssertEqual(videosEnAudio, 0)
        XCTAssertEqual(audiosEnAudio, 1)

        let preparado = carpeta.appendingPathComponent("preparado.mp4")
        try await Medios.prepararVideo(unido, destino: preparado)
        let videosPreparado = try await pistas(preparado, .video)
        XCTAssertEqual(videosPreparado, 1)

        let normalizado = carpeta.appendingPathComponent("normal.m4a")
        try await Medios.normalizarAudio(audio, destino: normalizado)
        let audiosNormal = try await pistas(normalizado, .audio)
        XCTAssertEqual(audiosNormal, 1)
    }
}
