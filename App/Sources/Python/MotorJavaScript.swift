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
    /// Ejecuta `script` en un contexto nuevo y devuelve la última línea escrita con
    /// `console.log` (el solucionador de yt-dlp imprime ahí su resultado en JSON).
    static func ejecutar(_ script: String) -> Result<String, ErrorJavaScript> {
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
