import Foundation
import JavaScriptCore

/// Error al ejecutar JavaScript.
struct ErrorJavaScript: Error, Equatable {
    let mensaje: String
}

/// Ejecuta JavaScript con JavaScriptCore, el motor que trae iOS.
///
/// Lo usa yt-dlp (a través de Python) para resolver los desafíos de YouTube. En una app
/// instalada así iOS no permite JIT, de modo que JavaScriptCore funciona en modo intérprete:
/// tarda unos segundos por video, pero funciona en cualquier hilo y también en segundo plano.
enum MotorJavaScript {
    private static let candado = NSLock()
    private static var generacion = 0

    /// Hace que las evaluaciones en curso dejen de esperarse (botón Cancelar de la descarga).
    static func cancelarEvaluaciones() {
        candado.lock(); generacion += 1; candado.unlock()
    }

    private static var generacionActual: Int {
        candado.lock(); defer { candado.unlock() }
        return generacion
    }

    /// Ejecuta `script` y devuelve la última línea escrita con `console.log` (el solucionador
    /// de yt-dlp imprime ahí su resultado en JSON).
    ///
    /// JavaScriptCore no se puede interrumpir con la API pública: el script corre en su propio
    /// hilo y aquí se espera como mucho `limite` segundos o hasta que se cancele. Así un desafío
    /// colgado nunca bloquea la app (yt-dlp sigue, aunque con menos formatos).
    static func ejecutar(_ script: String, limite: TimeInterval = 120) -> Result<String, ErrorJavaScript> {
        let inicioGeneracion = generacionActual
        let listo = DispatchSemaphore(value: 0)
        let caja = CajaResultado()
        let hilo = Thread {
            caja.valor = ejecutarAhora(script)
            listo.signal()
        }
        hilo.name = "JavaScriptCore"
        hilo.stackSize = 16 << 20  // el solucionador recorre árboles de sintaxis muy profundos
        hilo.start()

        let fin = Date().addingTimeInterval(limite)
        while listo.wait(timeout: .now() + 0.25) == .timedOut {
            if generacionActual != inicioGeneracion {
                return .failure(ErrorJavaScript(mensaje: "Cancelado"))
            }
            if Date() > fin {
                return .failure(ErrorJavaScript(mensaje: "El desafío de YouTube tardó más de \(Int(limite)) s"))
            }
        }
        return caja.valor
    }

    private final class CajaResultado {
        var valor: Result<String, ErrorJavaScript> = .failure(ErrorJavaScript(mensaje: "Sin resultado"))
    }

    /// Ejecuta en el hilo actual, en un contexto nuevo.
    private static func ejecutarAhora(_ script: String) -> Result<String, ErrorJavaScript> {
        guard let contexto = JSContext() else {
            return .failure(ErrorJavaScript(mensaje: "No se pudo crear el contexto de JavaScriptCore"))
        }
        let salida = Recolector()
        let errores = Recolector()
        var excepcion: String?

        contexto.exceptionHandler = { _, valor in
            let mensaje = valor?.toString() ?? "excepción desconocida"
            let pila = valor?.objectForKeyedSubscript("stack")?.toString() ?? ""
            excepcion = (pila.isEmpty || pila == "undefined") ? mensaje : "\(mensaje)\n\(pila)"
        }

        // console.log/info/debug van a la salida; console.warn/error, a los errores.
        let escribirSalida: @convention(block) () -> Void = { salida.agregar(Self.argumentosActuales()) }
        let escribirError: @convention(block) () -> Void = { errores.agregar(Self.argumentosActuales()) }
        if let consola = JSValue(newObjectIn: contexto) {
            for nombre in ["log", "info", "debug"] {
                consola.setObject(escribirSalida, forKeyedSubscript: nombre)
            }
            for nombre in ["warn", "error"] {
                consola.setObject(escribirError, forKeyedSubscript: nombre)
            }
            contexto.setObject(consola, forKeyedSubscript: "console" as NSString)
        }

        contexto.evaluateScript(script)

        if let excepcion {
            return .failure(ErrorJavaScript(mensaje: excepcion))
        }
        guard let ultima = salida.lineas.last(where: { !$0.isEmpty }) else {
            let detalle = errores.lineas.joined(separator: "\n")
            return .failure(ErrorJavaScript(mensaje: detalle.isEmpty ? "El script no escribió nada" : detalle))
        }
        return .success(ultima)
    }

    /// Argumentos de la llamada de console.* en curso, unidos por espacios.
    private static func argumentosActuales() -> String {
        let argumentos = (JSContext.currentArguments() as? [JSValue]) ?? []
        return argumentos.map { $0.toString() ?? "" }.joined(separator: " ")
    }

    /// Acumula líneas desde los bloques de console.* (clase para poder modificarla dentro).
    private final class Recolector {
        private(set) var lineas: [String] = []
        func agregar(_ linea: String) { lineas.append(linea) }
    }
}

/// Evaluador que se le pasa a Python (ver descargador/jsc.py). Se llama desde el hilo de Python.
let evaluadorJavaScript: dp_evaluador_js = { script, responder, contexto in
    guard let script, let responder else { return 1 }
    switch MotorJavaScript.ejecutar(String(cString: script)) {
    case .success(let salida):
        salida.withCString { responder($0, contexto) }
        return 0
    case .failure(let error):
        error.mensaje.withCString { responder($0, contexto) }
        return 1
    }
}
