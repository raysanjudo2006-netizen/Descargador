import Foundation

/// Error devuelto por el motor de descarga (Python + yt-dlp).
///
/// `codigo` lo decide descargador/errores.py a partir del mensaje de yt-dlp;
/// `mensaje` y `detalle` (traceback) son el texto original y van al Registro.
struct ErrorMotor: Error, Equatable {
    let codigo: String
    let mensaje: String
    let detalle: String?

    /// Texto en español para mostrar en la app.
    var mensajeUsuario: String {
        switch codigo {
        case "sin_conexion":
            return "No hay conexión o la web no responde. Revisa tu internet y vuelve a intentarlo."
        case "privado":
            return "El video es privado. Solo se puede descargar con tu propia sesión (cookies, en la Etapa 5)."
        case "requiere_sesion":
            return "La plataforma pide iniciar sesión o confirmar que no eres un robot. Prueba más tarde o usa tus cookies (Etapa 5)."
        case "geo":
            return "Este video no está disponible en tu país."
        case "no_disponible":
            return "El video no existe o fue eliminado."
        case "no_soportado":
            return "Este enlace no es de una web compatible."
        case "extractor":
            return "La plataforma cambió y yt-dlp no pudo leer el video. Habrá que actualizar yt-dlp (Etapa 5)."
        case "cancelado":
            return "Cancelado."
        case "interno":
            return "Error interno del motor de descarga. Copia el Registro y envíamelo."
        default:
            return "No se pudo analizar el video. Copia el Registro y envíamelo."
        }
    }
}

extension ErrorMotor: LocalizedError {
    var errorDescription: String? { mensajeUsuario }
}
