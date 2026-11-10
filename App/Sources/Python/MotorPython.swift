import Foundation

/// Algo capaz de analizar un enlace. En la app es `MotorPython`; en los tests, uno falso.
protocol AnalizadorVideo {
    func analizar(_ url: URL) async throws -> InfoVideo
}

/// Intérprete de Python embebido con yt-dlp.
///
/// - Python se inicializa una sola vez, en un hilo propio que nunca termina (es su
///   "hilo principal"). Después, cada llamada corre en su propio hilo con pila de 8 MB
///   y toma el GIL dentro de PuentePython.c.
/// - Los mensajes de yt-dlp llegan por un callback C y se anotan en el Registro.
final class MotorPython: AnalizadorVideo {
    static let compartido = MotorPython()

    private let registro: Registro
    private let candado = NSLock()
    private var inicio: Result<Void, ErrorMotor>?

    init(registro: Registro = .compartido) {
        self.registro = registro
    }

    // MARK: - API

    /// Versiones de Python, yt-dlp y yt-dlp-ejs.
    func version() async throws -> VersionesMotor {
        try await llamar("version", [:])
    }

    /// Analiza un enlace con yt-dlp. `permitirArchivos` solo se usa en los tests (file://).
    func info(url: URL, permitirArchivos: Bool = false) async throws -> InfoVideo {
        try await llamar("info", [
            "url": url.absoluteString,
            "permitir_archivos": permitirArchivos,
            "cache": Self.carpetaCache.path,
        ])
    }

    func analizar(_ url: URL) async throws -> InfoVideo {
        try await info(url: url)
    }

    /// Descarga las partes (video y/o audio) en `carpeta`, sin unirlas.
    /// `alProgreso` y `cancelado` se llaman desde el hilo de Python.
    func descargar(url: URL, partes: [ParteDescarga], carpeta: URL, permitirArchivos: Bool = false,
                   alProgreso: @escaping (ProgresoParte) -> Void,
                   cancelado: @escaping () -> Bool) async throws -> ResultadoDescargaPython {
        try await llamar("descargar", [
            "url": url.absoluteString,
            "partes": partes.map { ["parte": $0.parte, "formato": $0.formato] },
            "carpeta": carpeta.path,
            "cache": Self.carpetaCache.path,
            "permitir_archivos": permitirArchivos,
        ], eventos: ManejadorEventos(alProgreso: alProgreso, cancelado: cancelado))
    }

    /// Ejecuta JavaScript pasando por todo el camino Python → C → Swift → JavaScriptCore
    /// (para comprobar en los tests que yt-dlp podrá resolver los desafíos de YouTube).
    func probarJavaScript(_ script: String) async throws -> PruebaJavaScript {
        try await llamar("probar_js", ["script": script])
    }

    /// Lee la versión de yt-dlp (y la de yt-dlp-ejs que exige) de un zipapp o wheel descargado.
    func inspeccionarPaquete(_ archivo: URL) async throws -> PaqueteYtDlp {
        try await llamar("inspeccionar_paquete", ["ruta": archivo.path])
    }

    /// Caché de yt-dlp (firmas de YouTube, etc.).
    static var carpetaCache: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("yt-dlp", isDirectory: true)
    }

    // MARK: - Llamadas

    private func llamar<T: Decodable>(_ funcion: String, _ peticion: [String: Any],
                                      eventos: ManejadorEventos? = nil) async throws -> T {
        let json = String(decoding: try JSONSerialization.data(withJSONObject: peticion), as: UTF8.self)
        let inicioLlamada = Date()
        let respuesta: String = try await withCheckedThrowingContinuation { continuacion in
            let hilo = Thread { [self] in
                do {
                    try asegurarInicio()
                    continuacion.resume(returning: llamarSincrono(funcion, json, eventos))
                } catch {
                    continuacion.resume(throwing: error)
                }
            }
            hilo.name = "Python · \(funcion)"
            hilo.stackSize = 8 << 20
            hilo.start()
        }
        registro.depurar(String(format: "Python %@ respondió en %.1f s", funcion, Date().timeIntervalSince(inicioLlamada)),
                         categoria: "python")
        do {
            return try Self.decodificar(Data(respuesta.utf8))
        } catch let error as ErrorMotor where error.codigo == "cancelado" {
            registro.info("\(funcion): cancelado", categoria: "python")
            throw error
        } catch let error as ErrorMotor {
            registro.error("\(funcion): [\(error.codigo)] \(error.mensaje)", categoria: "python")
            if let detalle = error.detalle {
                registro.depurar(detalle, categoria: "python")
            }
            throw error
        }
    }

    /// Ejecuta la función en el hilo actual (bloquea hasta que Python termina).
    private func llamarSincrono(_ funcion: String, _ json: String, _ eventos: ManejadorEventos?) -> String {
        let caja = CajaEventos(registro: registro, eventos: eventos)
        let contexto = Unmanaged.passRetained(caja).toOpaque()
        defer { Unmanaged<CajaEventos>.fromOpaque(contexto).release() }
        guard let puntero = dp_llamar(funcion, json, callbackEventos, contexto) else {
            return #"{"ok":false,"error":{"codigo":"interno","mensaje":"Python no respondió"}}"#
        }
        defer { dp_liberar(puntero) }
        return String(cString: puntero)
    }

    /// Lee la respuesta {"ok": true, "datos": …} o {"ok": false, "error": …}.
    static func decodificar<T: Decodable>(_ datos: Data) throws -> T {
        let decodificador = JSONDecoder()
        decodificador.keyDecodingStrategy = .convertFromSnakeCase
        let respuesta: Respuesta<T>
        do {
            respuesta = try decodificador.decode(Respuesta<T>.self, from: datos)
        } catch {
            throw ErrorMotor(codigo: "interno", mensaje: "Respuesta de Python no válida: \(error)",
                             detalle: String(decoding: datos.prefix(2000), as: UTF8.self))
        }
        if respuesta.ok, let resultado = respuesta.datos {
            return resultado
        }
        let error = respuesta.error
        throw ErrorMotor(codigo: error?.codigo ?? "interno",
                         mensaje: error?.mensaje ?? "Respuesta sin datos",
                         detalle: error?.detalle)
    }

    // MARK: - Inicio de Python

    private func asegurarInicio() throws {
        candado.lock()
        defer { candado.unlock() }
        if let inicio {
            return try inicio.get()
        }
        let resultado = Self.iniciarEnHiloPropio()
        inicio = resultado
        switch resultado {
        case .success:
            registro.info("Python iniciado", categoria: "python")
            configurarJavaScript()
        case .failure(let error):
            registro.error(error.mensaje, categoria: "python")
        }
        try resultado.get()
    }

    /// Da a yt-dlp el motor JavaScriptCore para los desafíos de YouTube (ver descargador/jsc.py).
    /// Se llama una vez, justo después de arrancar Python y antes de cualquier análisis.
    private func configurarJavaScript() {
        let direccion = Int(truncatingIfNeeded: dp_direccion_evaluador(evaluadorJavaScript))
        let respuesta = llamarSincrono("configurar_js", #"{"evaluador": \#(direccion)}"#, nil)
        if !respuesta.contains(#""registrado": true"#) {
            registro.aviso("JavaScriptCore no quedó registrado en yt-dlp: \(respuesta.prefix(300))", categoria: "python")
        }
    }

    /// Inicializa Python en un hilo que se queda dormido para siempre.
    private static func iniciarEnHiloPropio() -> Result<Void, ErrorMotor> {
        let listo = DispatchSemaphore(value: 0)
        // Caja (clase) en vez de `var` capturada: el bloque de Thread puede ser @Sendable.
        let caja = CajaResultado()
        let hilo = Thread {
            caja.valor = iniciarPython()
            listo.signal()
            // Este es el hilo principal de Python: no debe terminar.
            DispatchSemaphore(value: 0).wait()
        }
        hilo.name = "Python · principal"
        hilo.stackSize = 8 << 20
        hilo.start()
        listo.wait()
        return caja.valor
    }

    private final class CajaResultado {
        var valor: Result<Void, ErrorMotor> = .failure(ErrorMotor(codigo: "interno", mensaje: "Python no arrancó", detalle: nil))
    }

    private static func iniciarPython() -> Result<Void, ErrorMotor> {
        let base = Bundle.main.bundleURL.appendingPathComponent("python", isDirectory: true)
        let lib = base.appendingPathComponent("lib", isDirectory: true)
        let contenido = (try? FileManager.default.contentsOfDirectory(atPath: lib.path)) ?? []
        guard let version = contenido.first(where: { $0.hasPrefix("python3.") }) else {
            return .failure(ErrorMotor(codigo: "interno", mensaje: "No se encontró Python dentro de la app", detalle: lib.path))
        }
        let stdlib = lib.appendingPathComponent(version, isDirectory: true)
        ActualizadorYtDlp.limpiarSinUso()
        // Orden de sys.path: biblioteca estándar, código de la app, yt-dlp actualizado desde
        // Ajustes (si lo hay) y, por último, los paquetes incluidos en la app.
        let rutas = ([
            stdlib.path,
            stdlib.appendingPathComponent("lib-dynload", isDirectory: true).path,
            base.appendingPathComponent("app", isDirectory: true).path,
        ] + ActualizadorYtDlp.rutasActivas() + [
            base.appendingPathComponent("app_packages", isDirectory: true).path,
        ]).joined(separator: "\n")

        let capacidad = 1024
        var error = [CChar](repeating: 0, count: capacidad)
        let codigo = dp_iniciar(base.path, rutas, &error, capacidad)
        guard codigo == 0 else {
            let motivo = String(decoding: error.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            return .failure(ErrorMotor(codigo: "interno", mensaje: "No se pudo iniciar Python: \(motivo)", detalle: rutas))
        }
        return .success(())
    }
}

// MARK: - Tipos internos

private struct Respuesta<T: Decodable>: Decodable {
    let ok: Bool
    let datos: T?
    let error: ErrorPython?
}

private struct ErrorPython: Decodable {
    let codigo: String
    let mensaje: String
    let detalle: String?
}

/// Evento que manda Python por el callback ("log" o "progreso").
private struct EventoPython: Decodable {
    let tipo: String
    let nivel: String?
    let mensaje: String?
    // Solo en "progreso":
    let parte: String?
    let estado: String?
    let descargado: Int64?
    let total: Int64?
    let estimado: Bool?
    let velocidad: Double?
    let eta: Double?
}

/// A quién avisar del progreso y cómo saber si hay que cancelar.
struct ManejadorEventos {
    let alProgreso: (ProgresoParte) -> Void
    let cancelado: () -> Bool
}

/// Contexto que viaja por C hasta el callback: aquí se reparten los eventos.
private final class CajaEventos {
    let registro: Registro
    let eventos: ManejadorEventos?

    init(registro: Registro, eventos: ManejadorEventos?) {
        self.registro = registro
        self.eventos = eventos
    }

    /// Devuelve true para pedir a Python que cancele.
    func recibir(_ json: String) -> Bool {
        guard let evento = try? JSONDecoder().decode(EventoPython.self, from: Data(json.utf8)) else {
            return eventos?.cancelado() ?? false
        }
        if evento.tipo == "progreso", let parte = evento.parte {
            eventos?.alProgreso(ProgresoParte(
                parte: parte,
                terminado: evento.estado == "terminado",
                descargado: evento.descargado ?? 0,
                total: evento.total,
                estimado: evento.estimado ?? false,
                velocidad: evento.velocidad,
                eta: evento.eta))
        } else if evento.tipo == "log" {
            let nivel: NivelRegistro
            switch evento.nivel {
            case "error": nivel = .error
            case "aviso": nivel = .aviso
            case "info": nivel = .info
            default: nivel = .depuracion
            }
            registro.registrar(nivel, evento.mensaje ?? "", categoria: "yt-dlp")
        }
        return eventos?.cancelado() ?? false
    }
}

/// Callback C que Python llama con cada evento (desde el hilo de Python).
private let callbackEventos: dp_callback = { evento, contexto in
    guard let evento, let contexto else { return 0 }
    let caja = Unmanaged<CajaEventos>.fromOpaque(contexto).takeUnretainedValue()
    return caja.recibir(String(cString: evento)) ? 1 : 0
}
