import CryptoKit
import XCTest
@testable import Descargador

/// Actualizar yt-dlp desde Ajustes (sin red: solo la lógica).
final class ActualizadorYtDlpTests: XCTestCase {
    func test_decodificaReleaseDeGitHub() throws {
        let json = """
        {"tag_name": "2026.11.03", "name": "yt-dlp 2026.11.03", "assets": [
          {"name": "yt-dlp", "size": 3070000, "digest": "sha256:abc",
           "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.03/yt-dlp"},
          {"name": "SHA2-256SUMS", "size": 900, "digest": null,
           "browser_download_url": "https://github.com/yt-dlp/yt-dlp/releases/download/2026.11.03/SHA2-256SUMS"}
        ]}
        """
        let decodificador = JSONDecoder()
        decodificador.keyDecodingStrategy = .convertFromSnakeCase
        let release = try decodificador.decode(ReleaseGitHub.self, from: Data(json.utf8))
        XCTAssertEqual(release.tagName, "2026.11.03")
        XCTAssertEqual(release.archivo("yt-dlp")?.size, 3_070_000)
        XCTAssertEqual(release.archivo("yt-dlp")?.digest, "sha256:abc")
        XCTAssertEqual(release.archivo("yt-dlp")?.browserDownloadUrl.lastPathComponent, "yt-dlp")
        XCTAssertNil(release.archivo("no-existe"))
    }

    func test_comparaVersiones() {
        XCTAssertTrue(ActualizadorYtDlp.esMasNueva("2026.11.03", que: "2026.10.26"))
        XCTAssertFalse(ActualizadorYtDlp.esMasNueva("2026.10.26", que: "2026.10.26"))
        XCTAssertFalse(ActualizadorYtDlp.esMasNueva("2026.10.21", que: "2026.10.26"))
        XCTAssertTrue(ActualizadorYtDlp.esMasNueva("2026.10.26.1", que: "2026.10.26"))
        XCTAssertTrue(ActualizadorYtDlp.esMasNueva("2027.01.01", que: "2026.12.31"))
    }

    func test_digestIncorrectoNoSeInstala() throws {
        let archivo = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let datos = Data("contenido de prueba".utf8)
        try datos.write(to: archivo)
        let correcto = "sha256:" + SHA256.hash(data: datos).map { String(format: "%02x", $0) }.joined()
        XCTAssertTrue(try ActualizadorYtDlp.coincideHuella(archivo, digest: correcto))
        XCTAssertTrue(try ActualizadorYtDlp.coincideHuella(archivo, digest: correcto.uppercased().replacingOccurrences(of: "SHA256:", with: "sha256:")))
        XCTAssertFalse(try ActualizadorYtDlp.coincideHuella(archivo, digest: "sha256:0000"))
    }

    func test_rutasActivasSoloSiExistenLosArchivos() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: carpeta.appendingPathComponent("2026.11.03"), withIntermediateDirectories: true)
        XCTAssertEqual(ActualizadorYtDlp.rutasActivas(en: carpeta), [], "Sin activo.json no hay rutas")

        let activo = InstalacionYtDlp(version: "2026.11.03", ejs: "0.9.0",
                                      archivoYtDlp: "2026.11.03/yt-dlp.zip", archivoEjs: "2026.11.03/ejs.whl")
        try JSONEncoder().encode(activo).write(to: carpeta.appendingPathComponent("activo.json"))
        XCTAssertEqual(ActualizadorYtDlp.rutasActivas(en: carpeta), [], "Faltan los archivos: no se usa")

        try Data().write(to: carpeta.appendingPathComponent("2026.11.03/yt-dlp.zip"))
        try Data().write(to: carpeta.appendingPathComponent("2026.11.03/ejs.whl"))
        let rutas = ActualizadorYtDlp.rutasActivas(en: carpeta)
        XCTAssertEqual(rutas.map { URL(fileURLWithPath: $0).lastPathComponent }, ["yt-dlp.zip", "ejs.whl"])
    }

    func test_limpiarSinUsoConservaLaActiva() throws {
        let carpeta = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        for nombre in ["2026.11.03-aaaa", "2026.10.30-bbbb"] {
            try FileManager.default.createDirectory(at: carpeta.appendingPathComponent(nombre), withIntermediateDirectories: true)
        }
        let activo = InstalacionYtDlp(version: "2026.11.03", ejs: nil,
                                      archivoYtDlp: "2026.11.03-aaaa/yt-dlp.zip", archivoEjs: nil)
        try JSONEncoder().encode(activo).write(to: carpeta.appendingPathComponent("activo.json"))
        ActualizadorYtDlp.limpiarSinUso(en: carpeta)
        let quedan = try FileManager.default.contentsOfDirectory(atPath: carpeta.path).sorted()
        XCTAssertEqual(quedan, ["2026.11.03-aaaa", "activo.json"])
    }

    func test_ejsIncluidoSeLeeDeLaApp() {
        // En el simulador la app lleva yt-dlp-ejs 0.8.0 dentro (python/app_packages).
        XCTAssertEqual(ActualizadorYtDlp.ejsIncluido, "0.8.0")
    }

    func test_versionesMotorDetectaYtDlpActualizado() throws {
        let json = #"{"ok":true,"datos":{"python":"3.14.10","yt_dlp":"2026.11.03","yt_dlp_ejs":"0.8.0","ruta_yt_dlp":"/var/mobile/Containers/Data/Application/X/Library/Application Support/yt-dlp/2026.11.03/yt-dlp.zip/yt_dlp"}}"#
        let versiones: VersionesMotor = try MotorPython.decodificar(Data(json.utf8))
        XCTAssertTrue(versiones.ytDlpActualizado)
    }
}
