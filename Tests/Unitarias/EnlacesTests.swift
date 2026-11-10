import XCTest
@testable import Descargador

/// Extracción de enlaces de texto pegado/compartido y lectura del esquema descargador://.
final class EnlacesTests: XCTestCase {
    private func peticion(_ texto: String) -> PeticionDescarga? {
        guard let url = URL(string: texto) else {
            XCTFail("URL de prueba inválida: \(texto)")
            return nil
        }
        return Enlaces.peticion(desde: url)
    }

    // MARK: - extraerPrimerEnlace

    func test_extraeEnlaceDeTextoCompartidoDeTikTok() {
        let url = Enlaces.extraerPrimerEnlace(de: "Mira esto 😂 https://vm.tiktok.com/ZMabc123/ #fyp")
        XCTAssertEqual(url?.absoluteString, "https://vm.tiktok.com/ZMabc123/")
    }

    func test_textoSinEnlaceDevuelveNil() {
        XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "hola mundo"))
        XCTAssertNil(Enlaces.extraerPrimerEnlace(de: ""))
    }

    func test_ignoraEsquemasNoWeb() {
        XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "mailto:a@b.com"))
        XCTAssertNil(Enlaces.extraerPrimerEnlace(de: "ftp://x.com/a"))
    }

    func test_enlaceSinEsquema() {
        XCTAssertEqual(Enlaces.extraerPrimerEnlace(de: "youtu.be/dQw4w9WgXcQ")?.host, "youtu.be")
    }

    func test_espaciosYSaltosDeLinea() {
        let url = Enlaces.extraerPrimerEnlace(de: "  \nhttps://x.com/a/status/1\n ")
        XCTAssertEqual(url?.absoluteString, "https://x.com/a/status/1")
    }

    // MARK: - peticion(desde:)

    func test_peticionConUrlCodificadaYCalidad() {
        let p = peticion("descargador://download?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3Dabc%26t%3D10&calidad=720")
        XCTAssertEqual(p?.url.absoluteString, "https://www.youtube.com/watch?v=abc&t=10")
        XCTAssertEqual(p?.calidad, .p720)
    }

    func test_peticionConUrlSinCodificar() {
        let p = peticion("descargador://download?url=https://www.youtube.com/watch?v=abc&t=10")
        XCTAssertEqual(p?.url.absoluteString, "https://www.youtube.com/watch?v=abc&t=10")
        XCTAssertNil(p?.calidad)
    }

    func test_peticionConUrlSinCodificarYCalidad() {
        let p = peticion("descargador://download?url=https://www.youtube.com/watch?v=abc&t=10&calidad=audio")
        XCTAssertEqual(p?.url.absoluteString, "https://www.youtube.com/watch?v=abc&t=10")
        XCTAssertEqual(p?.calidad, .audio)
    }

    func test_peticionConCalidadAntesDeUrl() {
        let p = peticion("descargador://download?calidad=480&url=https://x.com/u/status/1")
        XCTAssertEqual(p?.url.absoluteString, "https://x.com/u/status/1")
        XCTAssertEqual(p?.calidad, .p480)
    }

    func test_peticionSinCodificarConservaPorcentajes() {
        let p = peticion("descargador://download?url=https://a.com/b%20c")
        XCTAssertEqual(p?.url.absoluteString, "https://a.com/b%20c")
    }

    func test_peticionSinCodificarConservaFragmento() {
        let p = peticion("descargador://download?url=https://example.com/v#t=30")
        XCTAssertEqual(p?.url.absoluteString, "https://example.com/v#t=30")
    }

    func test_peticionCodificadaIgnoraOtrosParametros() {
        let p = peticion("descargador://download?url=https%3A%2F%2Fa.com%2Fv&origen=atajos&calidad=360")
        XCTAssertEqual(p?.url.absoluteString, "https://a.com/v")
        XCTAssertEqual(p?.calidad, .p360)
    }

    func test_peticionConTextoCompartidoEnteroDeTikTok() {
        // Un atajo que codifica el texto compartido completo, no solo el enlace.
        let p = peticion("descargador://download?url=Mira%20esto%20%F0%9F%98%82%20https%3A%2F%2Fvm.tiktok.com%2FZMabc%2F%20%23fyp&calidad=720")
        XCTAssertEqual(p?.url.absoluteString, "https://vm.tiktok.com/ZMabc/")
        XCTAssertEqual(p?.calidad, .p720)
    }

    func test_enlaceProfundoIdaYVuelta() throws {
        let originales = [
            "https://www.youtube.com/watch?v=abc&t=10#comentarios",
            "https://vm.tiktok.com/ZMabc/",
            "https://x.com/u/status/1?s=20&t=xyz",
        ]
        for texto in originales {
            let url = try XCTUnwrap(URL(string: texto))
            for calidad in [nil, Calidad.p720, .audio] {
                let profundo = Enlaces.enlaceProfundo(para: url, calidad: calidad)
                XCTAssertEqual(profundo.scheme, "descargador")
                XCTAssertEqual(Enlaces.peticion(desde: profundo), PeticionDescarga(url: url, calidad: calidad), profundo.absoluteString)
            }
        }
    }

    func test_peticionConCalidadDesconocida() {
        let p = peticion("descargador://download?url=https://a.com/v&calidad=4k")
        XCTAssertEqual(p?.url.absoluteString, "https://a.com/v")
        XCTAssertNil(p?.calidad)
    }

    func test_peticionesInvalidasDevuelvenNil() {
        XCTAssertNil(peticion("descargador://otra?url=https://a.com"))
        XCTAssertNil(peticion("descargador://download?url=javascript:alert(1)"))
        XCTAssertNil(peticion("https://download?url=https://a.com"))
        XCTAssertNil(peticion("descargador://download"))
        XCTAssertNil(peticion("descargador://download?url="))
    }
}
