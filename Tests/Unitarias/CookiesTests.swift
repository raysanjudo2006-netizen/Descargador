import XCTest
@testable import Descargador

/// Validación e importación de cookies.txt.
final class CookiesTests: XCTestCase {
    private let valido = """
    # Netscape HTTP Cookie File
    # Comentario
    .youtube.com\tTRUE\t/\tTRUE\t1893456000\tPREF\tf6=40000000
    #HttpOnly_.youtube.com\tTRUE\t/\tTRUE\t1893456000\tSID\tabc123

    """

    func test_cuentaCookiesValidas() {
        XCTAssertEqual(Cookies.contar(valido), 2)
    }

    func test_cookiesInvalidas() {
        XCTAssertEqual(Cookies.contar("hola\nesto no son cookies"), 0)
        XCTAssertEqual(Cookies.contar("# Netscape HTTP Cookie File\n# solo comentarios"), 0)
        XCTAssertEqual(Cookies.contar(#"[{"name":"SID","value":"x"}]"#), 0, "El formato JSON no vale")
    }

    func test_importarCopiaYRechazaLoInvalido() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let origen = carpeta.appendingPathComponent("cookies.txt")
        let destino = carpeta.appendingPathComponent("guardadas/cookies.txt")
        try valido.write(to: origen, atomically: true, encoding: .utf8)
        XCTAssertEqual(try Cookies.importar(desde: origen, destino: destino), 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destino.path))

        let malo = carpeta.appendingPathComponent("malo.txt")
        try "nada".write(to: malo, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Cookies.importar(desde: malo, destino: destino)) { error in
            XCTAssertEqual(error as? ErrorCookies, .formatoNoValido)
        }
        Cookies.borrar(destino)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destino.path))
    }
}
