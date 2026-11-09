import XCTest
@testable import Descargador

/// Nombres de archivo a partir de títulos de video.
final class NombresArchivoTests: XCTestCase {
    func test_nombreArchivoSeguro() {
        XCTAssertEqual(NombresArchivo.seguro("Mi video: parte 1/2"), "Mi video- parte 1-2")
        XCTAssertEqual(NombresArchivo.seguro("¿Qué? \"comillas\" <ok> | fin*"), "¿Qué- -comillas- -ok- - fin-")
        XCTAssertEqual(NombresArchivo.seguro("  muchos     espacios \n y salto  "), "muchos espacios y salto")
        XCTAssertEqual(NombresArchivo.seguro("...oculto"), "oculto")
        XCTAssertEqual(NombresArchivo.seguro(""), "video")
        XCTAssertEqual(NombresArchivo.seguro("🎬 Tráiler 😂"), "🎬 Tráiler 😂")
        XCTAssertEqual(NombresArchivo.seguro(String(repeating: "a", count: 200)).count, 80)
    }

    func test_emojisCompuestosNoSeRompen() {
        // 👨‍👩‍👧 lleva ZWJ (U+200D) entre los emojis: no debe convertirse en "-".
        XCTAssertEqual(NombresArchivo.seguro("Familia 👨‍👩‍👧"), "Familia 👨‍👩‍👧")
    }

    func test_tituloDeEmojisNoPasaDelLimiteDeBytes() {
        let titulo = String(repeating: "👩🏽‍💻", count: 80)  // ~15 bytes cada uno
        let nombre = NombresArchivo.seguro(titulo)
        XCTAssertLessThanOrEqual(nombre.utf8.count, 200)
        XCTAssertFalse(nombre.isEmpty)
    }

    func test_sinColisionNumeraLosRepetidos() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let primero = NombresArchivo.sinColision("Video", extension: "mp4", en: carpeta)
        XCTAssertEqual(primero.lastPathComponent, "Video.mp4")
        try Data().write(to: primero)
        let segundo = NombresArchivo.sinColision("Video", extension: "mp4", en: carpeta)
        XCTAssertEqual(segundo.lastPathComponent, "Video (2).mp4")
        try Data().write(to: segundo)
        XCTAssertEqual(NombresArchivo.sinColision("Video", extension: "mp4", en: carpeta).lastPathComponent, "Video (3).mp4")
    }

    func test_moverADescargasUsaElTitulo() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let origen = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        try Data([1, 2, 3]).write(to: origen)
        let final = try Guardado.moverADescargas(origen, titulo: "Hola/Mundo", carpeta: carpeta)
        XCTAssertEqual(final.lastPathComponent, "Hola-Mundo.mp4")
        XCTAssertFalse(FileManager.default.fileExists(atPath: origen.path))
        XCTAssertEqual(try Data(contentsOf: final), Data([1, 2, 3]))
    }
}
