import XCTest
@testable import Descargador

/// Analizador falso: responde lo que diga el test, sin Python.
private final class AnalizadorFalso: AnalizadorVideo {
    let responder: (URL) async throws -> InfoVideo

    init(_ responder: @escaping (URL) async throws -> InfoVideo) {
        self.responder = responder
    }

    func analizar(_ url: URL) async throws -> InfoVideo {
        try await responder(url)
    }
}

/// InfoVideo mínimo para los tests.
private func infoDePrueba(_ titulo: String) -> InfoVideo {
    InfoVideo(id: nil, titulo: titulo, autor: nil, duracion: nil, miniatura: nil, extractor: nil,
              urlPagina: nil, opciones: [], avisos: [])
}

/// Estado de la pantalla principal: analizar, pegar y abrir enlaces descargador://.
@MainActor
final class EstadoAppTests: XCTestCase {
    /// Crea un estado con un registro en un archivo temporal (no toca el registro real de la app).
    /// Por defecto, el análisis devuelve un video titulado como el enlace.
    private func nuevoEstado(
        analizador: AnalizadorVideo = AnalizadorFalso { url in infoDePrueba(url.absoluteString) }
    ) -> (EstadoApp, Registro) {
        let archivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("estado-\(UUID().uuidString).jsonl")
        let registro = Registro(archivo: archivo)
        return (EstadoApp(pestanaInicial: .ajustes, registro: registro, analizador: analizador), registro)
    }

    func test_analisisCorrectoPublicaInfo() async {
        let (estado, _) = nuevoEstado()
        estado.usarTextoPegado("https://x.com/u/status/1")
        XCTAssertEqual(estado.analisis, .analizando)
        await estado.esperarAnalisis()
        XCTAssertEqual(estado.analisis, .listo(infoDePrueba("https://x.com/u/status/1")))
    }

    func test_analisisFallidoMuestraMensajeEnEspanol() async {
        let error = ErrorMotor(codigo: "privado", mensaje: "Private video", detalle: nil)
        let (estado, _) = nuevoEstado(analizador: AnalizadorFalso { _ in throw error })
        estado.usarTextoPegado("https://youtu.be/abc")
        await estado.esperarAnalisis()
        XCTAssertEqual(estado.analisis, .fallo(error.mensajeUsuario))
    }

    func test_editarEnlaceCancelaAnalisis() {
        let (estado, _) = nuevoEstado()
        estado.usarTextoPegado("https://x.com/u/status/1")
        estado.textoEnlace = "https://x.com/u/status/2"
        XCTAssertEqual(estado.analisis, .inactivo)
    }

    func test_resultadoViejoNoPisaAlNuevo() async throws {
        let (estado, _) = nuevoEstado(analizador: AnalizadorFalso { url in
            if url.absoluteString.contains("lento") {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            return infoDePrueba(url.absoluteString)
        })
        estado.usarTextoPegado("https://x.com/lento")
        estado.usarTextoPegado("https://x.com/rapido")
        await estado.esperarAnalisis()
        try await Task.sleep(nanoseconds: 500_000_000)  // deja terminar al lento
        XCTAssertEqual(estado.analisis, .listo(infoDePrueba("https://x.com/rapido")))
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

    func test_editarTextoBorraCalidadPedida() throws {
        let (estado, _) = nuevoEstado()
        estado.abrir(enlaceProfundo: try XCTUnwrap(URL(string: "descargador://download?url=https://youtu.be/abc&calidad=720")))
        XCTAssertEqual(estado.calidadSolicitada, .p720)
        estado.textoEnlace = "https://x.com/u/status/9"
        estado.analizar()
        XCTAssertNil(estado.calidadSolicitada, "La calidad de Atajos no debe pasar a otro enlace escrito a mano")
    }

    func test_enlaceProfundoNoPasaPorElDetector() throws {
        // NSDataDetector recortaría el ")" final; el enlace ya validado debe llegar intacto.
        let (estado, _) = nuevoEstado()
        estado.abrir(enlaceProfundo: try XCTUnwrap(URL(string: "descargador://download?url=https://es.wikipedia.org/wiki/Hola_(saludo)")))
        XCTAssertEqual(estado.enlaceAnalizado?.absoluteString, "https://es.wikipedia.org/wiki/Hola_(saludo)")
    }

    func test_editarTextoBorraResultadoAnterior() {
        let (estado, _) = nuevoEstado()
        estado.usarTextoPegado("https://x.com/u/status/1")
        XCTAssertNotNil(estado.enlaceAnalizado)
        estado.textoEnlace = "https://youtu.be/otro"
        XCTAssertNil(estado.enlaceAnalizado, "Al cambiar el texto, la tarjeta del enlace anterior debe desaparecer")
    }
}
