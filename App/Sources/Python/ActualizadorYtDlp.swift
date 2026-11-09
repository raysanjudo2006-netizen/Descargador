import CryptoKit
import Foundation

/// Release de GitHub (solo los campos que se usan).
struct ReleaseGitHub: Decodable, Equatable {
    struct Archivo: Decodable, Equatable {
        let name: String
        let browserDownloadUrl: URL
        let size: Int
        /// "sha256:<hex>" (GitHub lo publica para cada archivo).
        let digest: String?
    }

    let tagName: String
    let assets: [Archivo]

    func archivo(_ nombre: String) -> Archivo? {
        assets.first { $0.name == nombre }
    }
}

/// yt-dlp instalado desde Ajustes (se guarda en activo.json).
struct InstalacionYtDlp: Codable, Equatable {
    let version: String
    let ejs: String?
    /// Rutas relativas a la carpeta del actualizador.
    let archivoYtDlp: String
    let archivoEjs: String?
}

enum ErrorActualizacion: LocalizedError, Equatable {
    case red(String)
    case huellaIncorrecta(String)
    case paqueteInesperado(String)

    var errorDescription: String? {
        switch self {
        case .red(let motivo): return "No se pudo descargar de GitHub: \(motivo)"
        case .huellaIncorrecta(let nombre): return "\(nombre) llegó dañado (la huella SHA-256 no coincide). Vuelve a intentarlo."
        case .paqueteInesperado(let motivo): return "El archivo descargado no es el esperado: \(motivo)"
        }
    }
}

/// Actualiza yt-dlp sin reinstalar la app.
///
/// yt-dlp es Python puro: el zipapp `yt-dlp` de su release de GitHub se puede importar
/// directamente (zipimport). Se guarda en Application Support/yt-dlp y se pone por delante
/// del yt-dlp incluido en `sys.path` la próxima vez que arranca Python (al reabrir la app).
@MainActor
final class ActualizadorYtDlp: ObservableObject {
    enum Estado: Equatable {
        case inactivo
        case buscando
        case alDia(String)
        case disponible(String)
        case descargando(String)
        /// Instalada: hay que cerrar y abrir la app para usarla.
        case instalada(String)
        case error(String)
    }

    @Published private(set) var estado: Estado = .inactivo
    /// Versión instalada desde Ajustes que está activa (nil = la incluida en la app).
    @Published private(set) var instalada: InstalacionYtDlp?

    private let carpeta: URL
    private let sesion: URLSession
    private let registro: Registro
    private var ultimaRelease: ReleaseGitHub?

    nonisolated static var carpetaPorDefecto: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("yt-dlp", isDirectory: true)
    }

    init(carpeta: URL = ActualizadorYtDlp.carpetaPorDefecto, sesion: URLSession = .shared,
         registro: Registro = .compartido) {
        self.carpeta = carpeta
        self.sesion = sesion
        self.registro = registro
        self.instalada = Self.leerActivo(en: carpeta)
    }

    // MARK: - Rutas para Python (se llama desde el hilo de Python al arrancar)

    /// Archivos que van primero en sys.path, si hay una versión instalada y sus archivos existen.
    nonisolated static func rutasActivas(en carpeta: URL = carpetaPorDefecto) -> [String] {
        guard let activo = leerActivo(en: carpeta) else { return [] }
        let rutas = [activo.archivoYtDlp] + (activo.archivoEjs.map { [$0] } ?? [])
        let completas = rutas.map { carpeta.appendingPathComponent($0).path }
        return completas.allSatisfy { FileManager.default.fileExists(atPath: $0) } ? completas : []
    }

    /// Borra las versiones descargadas que ya no se usan. Se llama al arrancar Python, antes de
    /// importar nada: nunca se borra un archivo que el intérprete en marcha esté usando.
    nonisolated static func limpiarSinUso(en carpeta: URL = carpetaPorDefecto) {
        let enUso = leerActivo(en: carpeta).map { activo in
            activo.archivoYtDlp.split(separator: "/").first.map(String.init) ?? ""
        }
        let contenido = (try? FileManager.default.contentsOfDirectory(atPath: carpeta.path)) ?? []
        for nombre in contenido where nombre != "activo.json" && nombre != enUso {
            try? FileManager.default.removeItem(at: carpeta.appendingPathComponent(nombre))
        }
    }

    /// Versión de yt-dlp-ejs que viene dentro de la app (de su carpeta .dist-info).
    nonisolated static var ejsIncluido: String? {
        let paquetes = Bundle.main.bundleURL.appendingPathComponent("python/app_packages", isDirectory: true)
        let nombres = (try? FileManager.default.contentsOfDirectory(atPath: paquetes.path)) ?? []
        guard let info = nombres.first(where: { $0.hasPrefix("yt_dlp_ejs-") && $0.hasSuffix(".dist-info") }) else {
            return nil
        }
        return String(info.dropFirst("yt_dlp_ejs-".count).dropLast(".dist-info".count))
    }

    nonisolated private static func leerActivo(en carpeta: URL) -> InstalacionYtDlp? {
        guard let datos = try? Data(contentsOf: carpeta.appendingPathComponent("activo.json")) else { return nil }
        return try? JSONDecoder().decode(InstalacionYtDlp.self, from: datos)
    }

    // MARK: - Acciones

    /// Consulta la última versión en GitHub y la compara con la que está funcionando.
    func buscar(versionActual: String) async {
        estado = .buscando
        do {
            let release = try await obtenerRelease("https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")
            ultimaRelease = release
            estado = Self.esMasNueva(release.tagName, que: versionActual) ? .disponible(release.tagName) : .alDia(release.tagName)
            registro.info("yt-dlp en GitHub: \(release.tagName) (en uso: \(versionActual))", categoria: "actualizar")
        } catch {
            fallo(error)
        }
    }

    /// Descarga, verifica e instala la versión encontrada por `buscar`.
    func instalar() async {
        guard let release = ultimaRelease, let zipapp = release.archivo("yt-dlp") else {
            estado = .error("Primero busca la actualización.")
            return
        }
        let version = release.tagName
        // Carpeta nueva en cada instalación: si falla, solo se borra ella (nunca la activa).
        let nombreCarpeta = "\(version)-\(UUID().uuidString.prefix(8))"
        let destino = carpeta.appendingPathComponent(nombreCarpeta, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: destino, withIntermediateDirectories: true)

            estado = .descargando("Descargando yt-dlp \(version) (\(Formato.bytes(Int64(zipapp.size))))…")
            let rutaZip = destino.appendingPathComponent("yt-dlp.zip")
            try await descargarVerificado(zipapp, a: rutaZip)

            estado = .descargando("Comprobando el paquete…")
            let paquete = try await MotorPython.compartido.inspeccionarPaquete(rutaZip)
            guard paquete.ytDlp == version else {
                throw ErrorActualizacion.paqueteInesperado("dice ser yt-dlp \(paquete.ytDlp)")
            }

            // yt-dlp exige una versión exacta de yt-dlp-ejs (el solucionador de YouTube).
            // Si no es la que trae la app, se descarga junto a esta versión.
            var archivoEjs: String?
            if let ejs = paquete.ejs, !paquete.incluyeEjs, ejs != Self.ejsIncluido {
                estado = .descargando("Descargando yt-dlp-ejs \(ejs)…")
                let releaseEjs = try await obtenerRelease("https://api.github.com/repos/yt-dlp/ejs/releases/tags/\(ejs)")
                let nombreWheel = "yt_dlp_ejs-\(ejs)-py3-none-any.whl"
                guard let wheel = releaseEjs.archivo(nombreWheel) else {
                    throw ErrorActualizacion.paqueteInesperado("falta \(nombreWheel) en GitHub")
                }
                try await descargarVerificado(wheel, a: destino.appendingPathComponent(nombreWheel))
                archivoEjs = "\(nombreCarpeta)/\(nombreWheel)"
            }

            let activo = InstalacionYtDlp(version: version, ejs: paquete.ejs,
                                          archivoYtDlp: "\(nombreCarpeta)/yt-dlp.zip", archivoEjs: archivoEjs)
            try JSONEncoder().encode(activo).write(to: carpeta.appendingPathComponent("activo.json"), options: .atomic)
            // Las versiones anteriores se borran al próximo arranque (pueden estar en uso ahora).
            instalada = activo
            estado = .instalada(version)
            registro.info("yt-dlp \(version) instalado; se usará al reabrir la app", categoria: "actualizar")
        } catch {
            try? FileManager.default.removeItem(at: destino)
            fallo(error)
        }
    }

    /// Quita la versión instalada: al reabrir la app se usa la incluida. Sus archivos se
    /// borran en el próximo arranque (ahora mismo pueden estar en uso).
    func volverAIncluida() {
        try? FileManager.default.removeItem(at: carpeta.appendingPathComponent("activo.json"))
        instalada = nil
        estado = .inactivo
        registro.info("Se usará el yt-dlp incluido al reabrir la app", categoria: "actualizar")
    }

    // MARK: - Utilidades

    /// "2026.11.03" es más nueva que "2026.10.26"; también entiende "2026.10.26.1".
    nonisolated static func esMasNueva(_ candidata: String, que actual: String) -> Bool {
        let a = candidata.split(separator: ".").map { Int($0) ?? 0 }
        let b = actual.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Compara el SHA-256 de un archivo con el "sha256:<hex>" que publica GitHub.
    nonisolated static func coincideHuella(_ archivo: URL, digest: String) throws -> Bool {
        let esperado = digest.lowercased().replacingOccurrences(of: "sha256:", with: "")
        let calculado = SHA256.hash(data: try Data(contentsOf: archivo)).map { String(format: "%02x", $0) }.joined()
        return calculado == esperado
    }

    private func obtenerRelease(_ direccion: String) async throws -> ReleaseGitHub {
        guard let url = URL(string: direccion) else { throw ErrorActualizacion.red("dirección no válida") }
        var peticion = URLRequest(url: url)
        peticion.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (datos, respuesta) = try await sesion.data(for: peticion)
        let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
        guard codigo == 200 else { throw ErrorActualizacion.red("GitHub respondió \(codigo)") }
        let decodificador = JSONDecoder()
        decodificador.keyDecodingStrategy = .convertFromSnakeCase
        return try decodificador.decode(ReleaseGitHub.self, from: datos)
    }

    /// Descarga con hasta 3 intentos (la conexión puede cortarse) y comprueba la huella.
    private func descargarVerificado(_ archivo: ReleaseGitHub.Archivo, a destino: URL) async throws {
        var ultimoError: Error = ErrorActualizacion.red("sin intentos")
        for intento in 1...3 {
            do {
                let (temporal, respuesta) = try await sesion.download(from: archivo.browserDownloadUrl)
                let codigo = (respuesta as? HTTPURLResponse)?.statusCode ?? 0
                guard codigo == 200 else { throw ErrorActualizacion.red("HTTP \(codigo)") }
                try? FileManager.default.removeItem(at: destino)
                try FileManager.default.moveItem(at: temporal, to: destino)
                if let digest = archivo.digest, try !Self.coincideHuella(destino, digest: digest) {
                    try? FileManager.default.removeItem(at: destino)
                    throw ErrorActualizacion.huellaIncorrecta(archivo.name)
                }
                return
            } catch {
                ultimoError = error
                registro.aviso("Descarga de \(archivo.name) falló (intento \(intento) de 3): \(error.localizedDescription)",
                               categoria: "actualizar")
            }
        }
        throw ultimoError
    }

    private func fallo(_ error: Error) {
        let mensaje = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        estado = .error(mensaje)
        registro.error("Actualizar yt-dlp: \(error)", categoria: "actualizar")
    }
}
