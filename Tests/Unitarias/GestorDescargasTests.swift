import XCTest
@testable import Descargador

/// Motor falso: hace lo que diga cada test, sin Python ni red.
private final class MotorFalso: MotorDescargas {
    typealias Accion = (_ partes: [ParteDescarga], _ alProgreso: (ProgresoParte) -> Void,
                        _ cancelado: () -> Bool) async throws -> ResultadoDescargaPython
    let accion: Accion

    init(_ accion: @escaping Accion) {
        self.accion = accion
    }

    func descargar(url: URL, partes: [ParteDescarga], carpeta: URL, permitirArchivos: Bool,
                   alProgreso: @escaping (ProgresoParte) -> Void,
                   cancelado: @escaping () -> Bool) async throws -> ResultadoDescargaPython {
        try await accion(partes, alProgreso, cancelado)
    }
}

/// Flujo completo de una descarga: progreso, cancelación, errores y archivo final.
@MainActor
final class GestorDescargasTests: XCTestCase {
    private let enlace = URL(string: "https://x.com/u/status/1")!

    private func gestor(_ motor: MotorFalso) -> GestorDescargas {
        let archivo = FileManager.default.temporaryDirectory.appendingPathComponent("gestor-\(UUID().uuidString).jsonl")
        let temporal = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        return GestorDescargas(motor: motor, registro: Registro(archivo: archivo), carpetaTemporal: temporal,
                               pedirPermisos: false)
    }

    private func opcion(_ calidad: String = "mejor", video: String? = "v", audio: String? = nil,
                        unir: Bool = false, extraerAudio: Bool = false) -> OpcionCalidad {
        OpcionCalidad(calidad: calidad, disponible: true, resolucion: 720, video: video, audio: audio,
                      unir: unir, bytes: 1_000, aproximado: false, protocolo: "https", extraerAudio: extraerAudio)
    }

    private let info = InfoVideo(id: "1", titulo: "Video de prueba", autor: nil, duracion: 1, miniatura: nil,
                                 extractor: nil, urlPagina: nil, opciones: [], avisos: [])

    /// Video MP4 con audio, generado en el simulador.
    private func videoConAudio() async throws -> URL {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let video = carpeta.appendingPathComponent("v.mp4")
        let audio = carpeta.appendingPathComponent("a.m4a")
        let unido = carpeta.appendingPathComponent("unido.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        try GeneradorMedios.audio(segundos: 1, en: audio)
        try await Medios.unir(video: video, audio: audio, destino: unido)
        return unido
    }

    func test_partesYCarpetaDeUnaOpcion() {
        XCTAssertEqual(GestorDescargas.partes(de: opcion(video: "137", audio: "140", unir: true)),
                       [ParteDescarga(parte: "video", formato: "137"), ParteDescarga(parte: "audio", formato: "140")])
        XCTAssertEqual(GestorDescargas.nombreCarpeta(url: enlace, calidad: "720"),
                       GestorDescargas.nombreCarpeta(url: enlace, calidad: "720"))
        XCTAssertNotEqual(GestorDescargas.nombreCarpeta(url: enlace, calidad: "720"),
                          GestorDescargas.nombreCarpeta(url: enlace, calidad: "480"))
    }

    func test_cancelarTerminaEnCanceladaYSePuedeCerrar() async {
        let gestor = gestor(MotorFalso { _, _, cancelado in
            while !cancelado() { try await Task.sleep(nanoseconds: 10_000_000) }
            throw ErrorMotor(codigo: "cancelado", mensaje: "Cancelado", detalle: nil)
        })
        gestor.iniciar(info: info, opcion: opcion(), url: enlace, guardarEnFotos: false, mantenerActivo: false)
        XCTAssertTrue(gestor.ocupado)
        gestor.cancelar()
        await gestor.esperar()
        XCTAssertEqual(gestor.fase, .cancelada)
        gestor.cerrar()
        XCTAssertEqual(gestor.fase, .inactiva)
    }

    func test_falloMuestraMensajeEnEspanol() async {
        let error = ErrorMotor(codigo: "sin_conexion", mensaje: "urlopen error", detalle: nil)
        let gestor = gestor(MotorFalso { _, _, _ in throw error })
        gestor.iniciar(info: info, opcion: opcion(), url: enlace, guardarEnFotos: false, mantenerActivo: false)
        await gestor.esperar()
        XCTAssertEqual(gestor.fase, .fallida(error.mensajeUsuario))
    }

    func test_descargaDeVideoCompleta() async throws {
        let descargado = try await videoConAudio()
        let gestor = gestor(MotorFalso { partes, alProgreso, _ in
            alProgreso(ProgresoParte(parte: "video", terminado: true, descargado: 1_000, total: 1_000,
                                     estimado: false, velocidad: nil, eta: nil))
            return ResultadoDescargaPython(archivos: ["video": descargado.path], titulo: "Video de prueba", id: "1")
        })
        gestor.iniciar(info: info, opcion: opcion(), url: enlace, guardarEnFotos: false, mantenerActivo: false)
        await gestor.esperar()
        guard case .terminada(let final) = gestor.fase else {
            return XCTFail("Fase inesperada: \(gestor.fase)")
        }
        defer { try? FileManager.default.removeItem(at: final.archivo) }
        XCTAssertFalse(final.esAudio)
        XCTAssertFalse(final.enFotos)
        XCTAssertEqual(final.archivo.pathExtension, "mp4")
        XCTAssertTrue(final.archivo.lastPathComponent.hasPrefix("Video de prueba"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: final.archivo.path))
    }

    func test_soloAudioExtraidoDelVideo() async throws {
        let descargado = try await videoConAudio()
        let gestor = gestor(MotorFalso { _, _, _ in
            ResultadoDescargaPython(archivos: ["video": descargado.path], titulo: nil, id: nil)
        })
        gestor.iniciar(info: info, opcion: opcion("audio", extraerAudio: true), url: enlace,
                       guardarEnFotos: true, mantenerActivo: false)
        await gestor.esperar()
        guard case .terminada(let final) = gestor.fase else {
            return XCTFail("Fase inesperada: \(gestor.fase)")
        }
        defer { try? FileManager.default.removeItem(at: final.archivo) }
        XCTAssertTrue(final.esAudio)
        XCTAssertFalse(final.enFotos, "El audio nunca va a Fotos")
        XCTAssertEqual(final.archivo.pathExtension, "m4a")
    }

    func test_noSeIniciaOtraMientrasHayUnaEnCurso() async {
        let gestor = gestor(MotorFalso { _, _, cancelado in
            while !cancelado() { try await Task.sleep(nanoseconds: 10_000_000) }
            throw CancellationError()
        })
        gestor.iniciar(info: info, opcion: opcion(), url: enlace, guardarEnFotos: false, mantenerActivo: false)
        let otro = InfoVideo(id: "2", titulo: "Otro", autor: nil, duracion: nil, miniatura: nil, extractor: nil,
                             urlPagina: nil, opciones: [], avisos: [])
        gestor.iniciar(info: otro, opcion: opcion(), url: enlace, guardarEnFotos: false, mantenerActivo: false)
        XCTAssertEqual(gestor.titulo, "Video de prueba")
        gestor.cancelar()
        await gestor.esperar()
    }
}
