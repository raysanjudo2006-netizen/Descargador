import XCTest
@testable import Descargador

/// Lectura de las respuestas JSON del puente de Python.
final class InfoVideoTests: XCTestCase {
    private let ejemplo = """
    {"ok": true, "datos": {
      "id": "abc", "titulo": "Un video", "autor": "Alguien", "duracion": 3723.4,
      "miniatura": "https://i.ytimg.com/vi/abc/hq.jpg", "extractor": "Youtube",
      "url_pagina": "https://www.youtube.com/watch?v=abc", "avisos": ["aviso 1"],
      "opciones": [
        {"calidad": "mejor", "disponible": true, "resolucion": 1080, "video": "137", "audio": "140",
         "unir": true, "bytes": 52428800, "aproximado": false, "protocolo": "https", "extraer_audio": false},
        {"calidad": "audio", "disponible": true, "resolucion": null, "video": null, "audio": "140",
         "unir": false, "bytes": null, "aproximado": true, "protocolo": "https", "extraer_audio": false}
      ]}}
    """

    func test_decodificaInfoCompleta() throws {
        let info: InfoVideo = try MotorPython.decodificar(Data(ejemplo.utf8))
        XCTAssertEqual(info.titulo, "Un video")
        XCTAssertEqual(info.urlPagina, "https://www.youtube.com/watch?v=abc")
        XCTAssertEqual(info.urlMiniatura?.host, "i.ytimg.com")
        XCTAssertEqual(info.duracionTexto, "1:02:03")
        XCTAssertEqual(info.avisos, ["aviso 1"])
        let mejor = try XCTUnwrap(info.opcion(.mejor))
        XCTAssertEqual(mejor.tipo, .mejor)
        XCTAssertTrue(mejor.unir)
        XCTAssertEqual(mejor.resolucion, 1080)
        XCTAssertTrue(mejor.tamanoTexto?.contains("MB") ?? false, mejor.tamanoTexto ?? "nil")
        XCTAssertNil(info.opcion(.audio)?.tamanoTexto)
        XCTAssertNil(info.opcion(.p720))
    }

    func test_duracionCorta() throws {
        let json = #"{"ok":true,"datos":{"titulo":"t","duracion":225,"opciones":[],"avisos":[]}}"#
        let info: InfoVideo = try MotorPython.decodificar(Data(json.utf8))
        XCTAssertEqual(info.duracionTexto, "3:45")
    }

    func test_errorDePythonSeConvierteEnErrorMotor() {
        let json = #"{"ok":false,"error":{"codigo":"privado","mensaje":"Private video","detalle":null}}"#
        XCTAssertThrowsError(try MotorPython.decodificar(Data(json.utf8)) as InfoVideo) { error in
            let motor = error as? ErrorMotor
            XCTAssertEqual(motor?.codigo, "privado")
            XCTAssertTrue(motor?.mensajeUsuario.contains("privado") ?? false)
        }
    }

    func test_respuestaRotaEsErrorInterno() {
        XCTAssertThrowsError(try MotorPython.decodificar(Data("no es json".utf8)) as InfoVideo) { error in
            XCTAssertEqual((error as? ErrorMotor)?.codigo, "interno")
        }
    }
}
