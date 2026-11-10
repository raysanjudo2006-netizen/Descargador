import XCTest
@testable import Descargador

/// Historial de descargas en carpetas temporales.
@MainActor
final class HistorialStoreTests: XCTestCase {
    private struct Carpetas {
        let json: URL
        let archivos: URL
        let miniaturas: URL
    }

    private func carpetas() throws -> Carpetas {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archivos = base.appendingPathComponent("Descargas", isDirectory: true)
        try FileManager.default.createDirectory(at: archivos, withIntermediateDirectories: true)
        return Carpetas(json: base.appendingPathComponent("historial.json"), archivos: archivos,
                        miniaturas: base.appendingPathComponent("Miniaturas", isDirectory: true))
    }

    private func store(_ c: Carpetas) -> HistorialStore {
        HistorialStore(archivo: c.json, carpetaArchivos: c.archivos, carpetaMiniaturas: c.miniaturas)
    }

    private let enlace = URL(string: "https://x.com/u/status/1")!

    func test_agregarConMiniaturaYRecargar() async throws {
        let c = try carpetas()
        let video = c.archivos.appendingPathComponent("Mi video.mp4")
        try await GeneradorMedios.video(segundos: 2, en: video)
        let historial = store(c)
        let resultado = ResultadoFinal(archivo: video, titulo: "Mi video", esAudio: false, enFotos: true, avisoFotos: nil)
        await historial.agregar(resultado, plataforma: .x, calidad: .p720, enlace: enlace)

        XCTAssertEqual(historial.entradas.count, 1)
        let entrada = try XCTUnwrap(historial.entradas.first)
        XCTAssertEqual(entrada.nombreArchivo, "Mi video.mp4")
        XCTAssertGreaterThan(entrada.bytes, 0)
        XCTAssertTrue(historial.existeArchivo(entrada))
        let miniatura = try XCTUnwrap(historial.urlMiniatura(entrada))
        XCTAssertTrue(FileManager.default.fileExists(atPath: miniatura.path), "Debe generar la miniatura del video")

        let recargado = store(c)
        XCTAssertEqual(recargado.entradas, historial.entradas)
    }

    func test_entradaSinArchivo() async throws {
        let c = try carpetas()
        let audio = c.archivos.appendingPathComponent("Canción.m4a")
        try GeneradorMedios.audio(segundos: 1, en: audio)
        let historial = store(c)
        await historial.agregar(ResultadoFinal(archivo: audio, titulo: "Canción", esAudio: true, enFotos: false, avisoFotos: nil),
                                plataforma: .youtube, calidad: .audio, enlace: enlace)
        let entrada = try XCTUnwrap(historial.entradas.first)
        XCTAssertNil(entrada.nombreMiniatura, "El audio no lleva miniatura")
        try FileManager.default.removeItem(at: audio)  // borrado desde la app Archivos
        XCTAssertFalse(historial.existeArchivo(entrada))
    }

    func test_borrarQuitaArchivoYEntrada() async throws {
        let c = try carpetas()
        let video = c.archivos.appendingPathComponent("v.mp4")
        try await GeneradorMedios.video(segundos: 1, en: video)
        let historial = store(c)
        await historial.agregar(ResultadoFinal(archivo: video, titulo: "v", esAudio: false, enFotos: false, avisoFotos: nil),
                                plataforma: .otra, calidad: nil, enlace: enlace)
        let entrada = try XCTUnwrap(historial.entradas.first)
        historial.borrar(entrada)
        XCTAssertTrue(historial.entradas.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: video.path))
        XCTAssertTrue(store(c).entradas.isEmpty)
    }

    func test_masNuevaPrimeroYVaciar() async throws {
        let c = try carpetas()
        let historial = store(c)
        for nombre in ["a", "b"] {
            let audio = c.archivos.appendingPathComponent("\(nombre).m4a")
            try GeneradorMedios.audio(segundos: 1, en: audio)
            await historial.agregar(ResultadoFinal(archivo: audio, titulo: nombre, esAudio: true, enFotos: false, avisoFotos: nil),
                                    plataforma: .tiktok, calidad: .audio, enlace: enlace)
        }
        XCTAssertEqual(historial.entradas.map(\.titulo), ["b", "a"])
        historial.vaciar()
        XCTAssertTrue(historial.entradas.isEmpty)
    }
}
