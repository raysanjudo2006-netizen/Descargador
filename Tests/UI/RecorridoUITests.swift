import UIKit
import XCTest

/// Recorre la app en el simulador de GitHub Actions y guarda capturas de cada pantalla.
///
/// Las capturas se adjuntan al resultado (.xcresult) y el workflow las sube como el
/// artifact "capturas-simulador", para poder ver la app sin tener un Mac.
@MainActor
final class RecorridoUITests: XCTestCase {
    // MARK: - Ayudas

    /// Lanza la app con argumentos (llegan a UserDefaults; ver DescargadorApp).
    private func lanzar(_ argumentos: [String]) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = argumentos
        app.launch()
        return app
    }

    /// Argumentos para que NO salga el aviso del portapapeles (marca el contenido actual como visto).
    private var sinAvisoPortapapeles: [String] {
        ["-ultimoCambioPortapapeles", String(UIPasteboard.general.changeCount)]
    }

    /// Adjunta una captura de pantalla con nombre (se conserva aunque el test pase).
    private func capturar(_ nombre: String) {
        let adjunto = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        adjunto.name = nombre
        adjunto.lifetime = .keepAlways
        add(adjunto)
    }

    private func elemento(_ app: XCUIApplication, _ identificador: String) -> XCUIElement {
        app.descendants(matching: .any)[identificador]
    }

    // MARK: - Tests

    func test_recorridoConCapturas() {
        for apariencia in ["claro", "oscuro"] {
            let app = lanzar(["-apariencia", apariencia, "-pestanaInicial", "descargar"] + sinAvisoPortapapeles)
            let campo = app.textFields["campoEnlace"]
            XCTAssertTrue(campo.waitForExistence(timeout: 15))
            capturar("01-descargar-\(apariencia)")

            app.tabBars.buttons["Historial"].tap()
            capturar("02-historial-\(apariencia)")

            app.tabBars.buttons["Ajustes"].tap()
            capturar("03-ajustes-\(apariencia)")

            app.tabBars.buttons["Registro"].tap()
            XCTAssertTrue(elemento(app, "listaRegistro").waitForExistence(timeout: 5),
                          "El registro debería tener al menos la entrada de inicio")
            capturar("04-registro-\(apariencia)")

            app.tabBars.buttons["Descargar"].tap()
            campo.tap()
            campo.typeText("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
            app.buttons["botonAnalizar"].tap()
            let etiqueta = app.staticTexts["etiquetaPlataforma"]
            XCTAssertTrue(etiqueta.waitForExistence(timeout: 5))
            XCTAssertEqual(etiqueta.label, "YouTube")
            capturar("05-analizado-\(apariencia)")

            app.terminate()
        }
    }

    func test_enlaceInvalidoMuestraError() {
        let app = lanzar(sinAvisoPortapapeles)
        let campo = app.textFields["campoEnlace"]
        XCTAssertTrue(campo.waitForExistence(timeout: 15))
        campo.tap()
        campo.typeText("hola")
        app.buttons["botonAnalizar"].tap()
        XCTAssertTrue(elemento(app, "mensajeError").waitForExistence(timeout: 5))
    }

    func test_bannerPortapapeles() {
        // Copiar algo nuevo cambia el changeCount, así que el aviso debe aparecer.
        UIPasteboard.general.string = "https://vm.tiktok.com/ZMabc/"
        let app = lanzar([])
        XCTAssertTrue(elemento(app, "bannerPortapapeles").waitForExistence(timeout: 10))
        capturar("06-banner-portapapeles")
    }

    func test_bannerPortapapelesNoSeRepite() {
        UIPasteboard.general.string = "https://x.com/u/status/2"
        var app = lanzar([])
        let banner = elemento(app, "bannerPortapapeles")
        XCTAssertTrue(banner.waitForExistence(timeout: 10))
        app.buttons["botonDescartarPortapapeles"].tap()
        let desaparece = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: banner)
        XCTAssertEqual(XCTWaiter().wait(for: [desaparece], timeout: 5), .completed, "El aviso debería ocultarse al descartarlo")
        app.terminate()

        // Al volver a abrir con el mismo portapapeles, el aviso no debe repetirse.
        app = lanzar([])
        XCTAssertTrue(app.textFields["campoEnlace"].waitForExistence(timeout: 15))
        XCTAssertFalse(elemento(app, "bannerPortapapeles").waitForExistence(timeout: 3))
    }

    func test_esquemaDeUrl() throws {
        guard #available(iOS 16.4, *) else { throw XCTSkip("XCUIApplication.open(_:) requiere iOS 16.4") }
        let app = lanzar(["-pestanaInicial", "ajustes"] + sinAvisoPortapapeles)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        let enlace = try XCTUnwrap(URL(string: "descargador://download?url=https%3A%2F%2Fx.com%2Fu%2Fstatus%2F1"))
        app.open(enlace)
        let etiqueta = app.staticTexts["etiquetaPlataforma"]
        XCTAssertTrue(etiqueta.waitForExistence(timeout: 10))
        XCTAssertEqual(etiqueta.label, "X")
        capturar("07-enlace-profundo")
    }
}
