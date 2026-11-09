import XCTest
@testable import Descargador

/// Detección de plataforma a partir del host del enlace.
final class PlataformaTests: XCTestCase {
    /// Comprueba que todos los enlaces de la lista se detectan como `esperada`.
    private func comprobar(_ esperada: Plataforma, _ enlaces: [String],
                           file: StaticString = #filePath, line: UInt = #line) {
        for texto in enlaces {
            guard let url = URL(string: texto) else {
                XCTFail("URL de prueba inválida: \(texto)", file: file, line: line)
                continue
            }
            XCTAssertEqual(Plataforma.detectar(url), esperada, texto, file: file, line: line)
        }
    }

    func test_youtube() {
        comprobar(.youtube, [
            "https://www.youtube.com/watch?v=a",
            "https://youtu.be/a",
            "https://m.youtube.com/shorts/a",
            "https://music.youtube.com/watch?v=a",
            "https://WWW.YOUTUBE.COM/watch?v=a",
        ])
    }

    func test_instagram() {
        comprobar(.instagram, [
            "https://www.instagram.com/reel/abc/",
            "https://instagr.am/p/abc",
        ])
    }

    func test_tiktok() {
        comprobar(.tiktok, [
            "https://www.tiktok.com/@u/video/1",
            "https://vm.tiktok.com/ZMabc/",
            "https://vt.tiktok.com/ZSabc/",
        ])
    }

    func test_x() {
        comprobar(.x, [
            "https://x.com/u/status/1",
            "https://twitter.com/u/status/1",
            "https://mobile.twitter.com/u/status/1",
        ])
    }

    func test_facebook() {
        comprobar(.facebook, [
            "https://www.facebook.com/watch/?v=1",
            "https://fb.watch/abc/",
            "https://m.facebook.com/story.php",
            "https://fb.com/x",
        ])
    }

    /// Hosts que se parecen pero no son la plataforma (trampas de sufijo).
    func test_otrasWebsYTrampas() {
        comprobar(.otra, [
            "https://vimeo.com/1",
            "https://notyoutube.com/a",
            "https://youtube.com.evil.net/a",
        ])
    }

    func test_nombresVisibles() {
        XCTAssertEqual(Plataforma.youtube.nombre, "YouTube")
        XCTAssertEqual(Plataforma.x.nombre, "X")
        XCTAssertEqual(Plataforma.otra.nombre, "Otra web")
    }
}
