import Combine
import XCTest
@testable import Descargador

/// Registro interno: persistencia, rotación y tolerancia a archivos dañados.
final class RegistroTests: XCTestCase {
    private var archivo: URL!

    override func setUp() {
        super.setUp()
        archivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("registro-\(UUID().uuidString).jsonl")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: archivo)
        super.tearDown()
    }

    private func lineasDelArchivo() -> [String] {
        let texto = (try? String(contentsOf: archivo, encoding: .utf8)) ?? ""
        return texto.split(separator: "\n").map(String.init)
    }

    func test_rotacionConservaLasUltimas() {
        let registro = Registro(archivo: archivo, maxEntradas: 10)
        for i in 0..<25 { registro.info("m\(i)") }
        registro.esperarEscrituras()

        XCTAssertEqual(registro.entradas.count, 10)
        XCTAssertLessThanOrEqual(lineasDelArchivo().count, 12)

        let recargado = Registro(archivo: archivo, maxEntradas: 10)
        XCTAssertEqual(recargado.entradas.count, 10)
        XCTAssertEqual(recargado.entradas.first?.mensaje, "m15")
        XCTAssertEqual(recargado.entradas.last?.mensaje, "m24")
    }

    func test_lineaCorruptaSeIgnora() throws {
        let registro = Registro(archivo: archivo)
        registro.info("primera")
        registro.aviso("segunda")
        registro.esperarEscrituras()

        // Simula un cierre inesperado: basura en medio y una línea final a medio escribir.
        let lineas = lineasDelArchivo()
        XCTAssertEqual(lineas.count, 2)
        let danado = [lineas[0], "{basura", lineas[1], "{\"id\":\"abc"].joined(separator: "\n")
        try danado.write(to: archivo, atomically: true, encoding: .utf8)

        let recargado = Registro(archivo: archivo)
        XCTAssertEqual(recargado.entradas.map(\.mensaje), ["primera", "segunda"])

        // Lo nuevo se sigue guardando bien aunque el archivo terminara a medias.
        recargado.error("tercera")
        recargado.esperarEscrituras()
        XCTAssertEqual(Registro(archivo: archivo).entradas.map(\.mensaje), ["primera", "segunda", "tercera"])
    }

    func test_textoCompletoIncluyeCabeceraYLineas() {
        let registro = Registro(archivo: archivo)
        registro.error("fallo", categoria: "prueba")
        let texto = registro.textoCompleto()
        XCTAssertTrue(texto.contains("Descargador"), texto)
        XCTAssertTrue(texto.contains("[ERROR] [prueba] fallo"), texto)
    }

    func test_limpiarVaciaMemoriaYArchivo() {
        let registro = Registro(archivo: archivo)
        registro.info("algo")
        registro.limpiar()
        registro.esperarEscrituras()
        XCTAssertTrue(registro.entradas.isEmpty)
        XCTAssertTrue(Registro(archivo: archivo).entradas.isEmpty)
    }

    func test_registroDesdeOtroHiloLlegaAMemoria() {
        let registro = Registro(archivo: archivo)
        let llegada = expectation(description: "entrada publicada en el hilo principal")
        let observador = registro.$entradas.dropFirst().sink { entradas in
            if entradas.last?.mensaje == "desde fondo" { llegada.fulfill() }
        }
        DispatchQueue.global().async { registro.depurar("desde fondo") }
        wait(for: [llegada], timeout: 2)
        observador.cancel()
    }
}
