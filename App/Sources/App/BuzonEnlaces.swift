import Foundation

/// Buzón para los enlaces que llegan desde Atajos (App Intents).
///
/// La acción puede ejecutarse antes de que exista la interfaz (la app estaba cerrada): el
/// enlace se guarda aquí y se entrega en cuanto `EstadoApp` se conecta. Si ya está
/// conectado, se entrega al momento.
@MainActor
final class BuzonEnlaces {
    static let compartido = BuzonEnlaces()

    private var pendiente: URL?
    private var receptor: ((URL) -> Void)?

    func depositar(_ enlace: URL) {
        if let receptor {
            receptor(enlace)
        } else {
            pendiente = enlace
        }
    }

    func conectar(_ receptor: @escaping (URL) -> Void) {
        self.receptor = receptor
        if let pendiente {
            self.pendiente = nil
            receptor(pendiente)
        }
    }
}
