import XCTest
@testable import Descargador

/// Suma del progreso de video y audio.
final class AcumuladorProgresoTests: XCTestCase {
    private func progreso(_ parte: String, _ descargado: Int64, _ total: Int64?, terminado: Bool = false,
                          estimado: Bool = false, velocidad: Double? = nil, eta: Double? = nil) -> ProgresoParte {
        ProgresoParte(parte: parte, terminado: terminado, descargado: descargado, total: total,
                      estimado: estimado, velocidad: velocidad, eta: eta)
    }

    func test_progresoDeDosPartes() {
        var acumulador = AcumuladorProgreso(partes: ["video", "audio"], estimacionTotal: 1_000)
        acumulador.actualizar(progreso("video", 400, 800, velocidad: 100))
        var r = acumulador.resumen
        // El audio aún no dio su total: se usa la estimación del análisis.
        XCTAssertEqual(r.total, 1_000)
        XCTAssertTrue(r.aproximado)
        XCTAssertEqual(r.fraccion, 0.4)
        XCTAssertEqual(r.parte, "video")
        XCTAssertEqual(r.numeroParte, 1)
        XCTAssertEqual(r.partes, 2)
        XCTAssertEqual(r.eta, 6)  // (1000 - 400) / 100

        acumulador.actualizar(progreso("video", 800, 800, terminado: true))
        acumulador.actualizar(progreso("audio", 100, 200, velocidad: 50))
        r = acumulador.resumen
        XCTAssertEqual(r.descargado, 900)
        XCTAssertEqual(r.total, 1_000)
        XCTAssertFalse(r.aproximado)
        XCTAssertEqual(r.numeroParte, 2)
        XCTAssertEqual(r.eta, 2)  // (1000 - 900) / 50
    }

    func test_progresoSinTotal() {
        var acumulador = AcumuladorProgreso(partes: ["video"], estimacionTotal: nil)
        acumulador.actualizar(progreso("video", 5_000, nil, eta: 7))
        let r = acumulador.resumen
        XCTAssertNil(r.total)
        XCTAssertNil(r.fraccion)
        XCTAssertEqual(r.descargado, 5_000)
        XCTAssertEqual(r.eta, 7, "Sin total se usa el tiempo restante que da yt-dlp")
    }

    func test_estimacionNuncaMenorQueLoDescargado() {
        var acumulador = AcumuladorProgreso(partes: ["video", "audio"], estimacionTotal: 100)
        acumulador.actualizar(progreso("video", 300, nil))
        XCTAssertEqual(acumulador.resumen.total, 300)
    }

    func test_alTerminarSinTotalSeUsaLoDescargado() {
        var acumulador = AcumuladorProgreso(partes: ["video"], estimacionTotal: nil)
        acumulador.actualizar(progreso("video", 1_234, nil, terminado: true))
        XCTAssertEqual(acumulador.resumen.total, 1_234)
        XCTAssertEqual(acumulador.resumen.fraccion, 1)
    }
}
