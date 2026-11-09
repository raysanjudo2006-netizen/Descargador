import UIKit

/// Portapapeles compartido por las pantallas.
///
/// Guarda el `changeCount` del último contenido ya ofrecido o copiado por la propia app,
/// para que el aviso "Tienes un enlace copiado" no ofrezca dos veces lo mismo ni ofrezca
/// lo que copiamos nosotros (el Registro, por ejemplo, contiene enlaces).
enum Portapapeles {
    /// Clave en UserDefaults (los UI tests la fijan con -ultimoCambioPortapapeles).
    static let claveUltimoCambio = "ultimoCambioPortapapeles"

    /// `changeCount` ya visto, o -1 si nunca se guardó.
    static var ultimoCambioVisto: Int {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: claveUltimoCambio) != nil else { return -1 }
        return defaults.integer(forKey: claveUltimoCambio)
    }

    /// Marca un contenido del portapapeles como ya visto.
    static func marcarVisto(_ cambio: Int) {
        UserDefaults.standard.set(cambio, forKey: claveUltimoCambio)
    }

    /// Copia texto desde la propia app sin que luego se ofrezca como "enlace copiado".
    static func copiar(_ texto: String) {
        UIPasteboard.general.string = texto
        marcarVisto(UIPasteboard.general.changeCount)
    }
}
