import XCTest
@testable import Descargador

/// Estado de la pantalla principal: analizar, pegar y abrir enlaces descargador://.
@MainActor
final class EstadoAppTests: XCTestCase {
    /// Crea un estado con un registro en un archivo temporal (no toca el registro real de la app).
    private func nuevoEstado() -> (EstadoApp, Registro) {
        let archivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("estado-\(UUID().uuidString).jsonl")
        let registro = Registro(archivo: archivo)
        return (EstadoApp(pestanaInicial: .ajustes, registro: registro), registro)
    }

    func test_abrirEnlaceProfundoRellenaYAnaliza() throws {
        let (estado, _) = nuevoEstado()
        let enlace = try XCTUnwrap(URL(string: "descargador://download?url=https://youtu.be/abc&calidad=720"))
        estado.abrir(enlaceProfundo: enlace)
        XCTAssertEqual(estado.pestana, .descargar)
        XCTAssertEqual(estado.textoEnlace, "https://youtu.be/abc")
        XCTAssertEqual(estado.enlaceAnalizado?.host, "youtu.be")
        XCTAssertEqual(estado.calidadSolicitada, .p720)
        XCTAssertNil(estado.mensajeError)
    }

    func test_analizarTextoInvalidoMuestraError() {
        let (estado, _) = nuevoEstado()
        estado.textoEnlace = "hola"
        estado.analizar()
        XCTAssertNil(estado.enlaceAnalizado)
        XCTAssertEqual(estado.mensajeError, "Eso no parece un enlace. Copia el enlace del video y pégalo aquí.")
    }

    func test_usarTextoPegadoExtraeEnlace() {
        let (estado, _) = nuevoEstado()
        estado.usarTextoPegado("mira https://x.com/u/status/1 jaja")
        XCTAssertEqual(estado.textoEnlace, "https://x.com/u/status/1")
        XCTAssertEqual(estado.enlaceAnalizado?.absoluteString, "https://x.com/u/status/1")
    }

    func test_enlaceProfundoInvalidoNoCambiaNada() throws {
        let (estado, registro) = nuevoEstado()
        estado.abrir(enlaceProfundo: try XCTUnwrap(URL(string: "descargador://otra")))
        XCTAssertEqual(estado.textoEnlace, "")
        XCTAssertEqual(estado.pestana, .ajustes)
        XCTAssertTrue(registro.entradas.contains { $0.nivel == .aviso })
    }

    func test_editarTextoBorraResultadoAnterior() {
        let (estado, _) = nuevoEstado()
        estado.usarTextoPegado("https://x.com/u/status/1")
        XCTAssertNotNil(estado.enlaceAnalizado)
        estado.textoEnlace = "https://youtu.be/otro"
        XCTAssertNil(estado.enlaceAnalizado, "Al cambiar el texto, la tarjeta del enlace anterior debe desaparecer")
    }
}
