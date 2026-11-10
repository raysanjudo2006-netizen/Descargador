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
    /// Devuelve false si ya no puede recibir (por ejemplo, su dueño desapareció).
    private var receptor: ((URL) -> Bool)?

    func depositar(_ enlace: URL) {
        if let receptor, receptor(enlace) {
            return
        }
        receptor = nil
        pendiente = enlace
    }

    func conectar(_ receptor: @escaping (URL) -> Bool) {
        self.receptor = receptor
        if let pendiente, receptor(pendiente) {
            self.pendiente = nil
        }
    }
}
