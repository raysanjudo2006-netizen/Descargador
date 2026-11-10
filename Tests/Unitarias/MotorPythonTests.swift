import XCTest
@testable import Descargador

/// Integración real: Python y yt-dlp dentro de la app, ejecutándose en el simulador.
/// No usan red: analizan un archivo .mp4 local.
final class MotorPythonTests: XCTestCase {
    private func archivoDePrueba() throws -> URL {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let archivo = carpeta.appendingPathComponent("muestra.mp4")
        try Data(count: 4096).write(to: archivo)
        return archivo
    }

    func test_versionesDelMotor() async throws {
        let versiones = try await MotorPython.compartido.version()
        XCTAssertTrue(versiones.python.hasPrefix("3.14"), versiones.python)
        XCTAssertEqual(versiones.ytDlp, "2026.10.26")
        XCTAssertEqual(versiones.ytDlpEjs, "0.8.0")
    }

    func test_infoDeArchivoLocal() async throws {
        let info = try await MotorPython.compartido.info(url: try archivoDePrueba(), permitirArchivos: true)
        XCTAssertEqual(info.titulo, "muestra")
        XCTAssertEqual(info.opcion(.mejor)?.disponible, true)
        XCTAssertEqual(info.opciones.count, 6)
    }

    func test_archivoLocalSinPermisoDaErrorLegible() async throws {
        let archivo = try archivoDePrueba()
        do {
            _ = try await MotorPython.compartido.info(url: archivo)
            XCTFail("yt-dlp no debería aceptar file:// sin permiso")
        } catch let error as ErrorMotor {
            XCTAssertNotEqual(error.codigo, "interno", "Debe ser un error de yt-dlp, no del puente: \(error.mensaje)")
            XCTAssertFalse(error.mensajeUsuario.isEmpty)
        }
    }

    /// Python → C → Swift → JavaScriptCore → Python: el camino que usa yt-dlp para YouTube.
    func test_javaScriptDesdePython() async throws {
        let prueba = try await MotorPython.compartido.probarJavaScript("console.log([1, 2, 3].map(x => x * 2).join('-'))")
        XCTAssertEqual(prueba.salida, "2-4-6")
    }

    func test_errorDeJavaScriptLlegaComoErrorMotor() async {
        do {
            _ = try await MotorPython.compartido.probarJavaScript("throw new Error('roto')")
            XCTFail("Debería fallar")
        } catch let error as ErrorMotor {
            XCTAssertTrue(error.mensaje.contains("roto"), error.mensaje)
        } catch {
            XCTFail("Error inesperado: \(error)")
        }
    }

    func test_llamadasEnParalelo() async throws {
        async let a = MotorPython.compartido.version()
        async let b = MotorPython.compartido.version()
        let (va, vb) = try await (a, b)
        XCTAssertEqual(va, vb)
    }
}
