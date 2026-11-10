import XCTest
@testable import Descargador

/// JavaScriptCore como motor de los desafíos de YouTube.
final class MotorJavaScriptTests: XCTestCase {
    func test_devuelveLaUltimaLineaDeConsoleLog() {
        let resultado = MotorJavaScript.ejecutar(#"console.log("primero"); console.log(JSON.stringify({a: 6 * 7}))"#)
        XCTAssertEqual(try resultado.get(), #"{"a":42}"#)
    }

    func test_excepcionDevuelveError() {
        guard case .failure(let error) = MotorJavaScript.ejecutar("noExiste()") else {
            return XCTFail("Debería fallar")
        }
        XCTAssertTrue(error.mensaje.contains("ReferenceError"), error.mensaje)
    }

    func test_sinSalidaEsError() {
        guard case .failure(let error) = MotorJavaScript.ejecutar("console.error('algo raro'); 1 + 1") else {
            return XCTFail("Sin console.log debería fallar")
        }
        XCTAssertTrue(error.mensaje.contains("algo raro"), error.mensaje)
    }

    func test_sintaxisModerna() {
        let script = """
        class A { #x = 1; get x() { return this.#x } }
        const o = { a: { b: null } };
        const v = o.a?.b ?? 'por defecto';
        const big = 2n ** 64n;
        console.log([new A().x, v, String(big), [1, [2, [3]]].flat(2).length].join(','));
        """
        XCTAssertEqual(try MotorJavaScript.ejecutar(script).get(), "1,por defecto,18446744073709551616,3")
    }

    /// El solucionador real de YouTube (yt-dlp-ejs, incluido en la app) debe cargar en
    /// JavaScriptCore igual que lo monta yt-dlp: lib + Object.assign(globalThis, lib) + core.
    func test_solucionadorDeYouTubeCargaEnJavaScriptCore() throws {
        let solver = Bundle.main.bundleURL.appendingPathComponent("python/app_packages/yt_dlp_ejs/yt/solver")
        let lib = try String(contentsOf: solver.appendingPathComponent("lib.min.js"), encoding: .utf8)
        let core = try String(contentsOf: solver.appendingPathComponent("core.min.js"), encoding: .utf8)
        let inicio = Date()
        let script = "\(lib)\nObject.assign(globalThis, lib);\n\(core)\nconsole.log(typeof jsc);"
        XCTAssertEqual(try MotorJavaScript.ejecutar(script).get(), "function")
        print("Solucionador de YouTube cargado en JavaScriptCore en \(Date().timeIntervalSince(inicio)) s")
    }
}
