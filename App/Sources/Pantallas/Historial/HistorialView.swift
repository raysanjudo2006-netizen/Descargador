import SwiftUI

/// Historial de descargas (la lista real llega en la Etapa 5).
struct HistorialView: View {
    var body: some View {
        NavigationStack {
            VistaVacia(
                titulo: "Sin descargas",
                simbolo: "tray",
                descripcion: "Los videos y audios que descargues aparecerán aquí para reproducirlos, compartirlos o borrarlos."
            )
            .navigationTitle("Historial")
        }
    }
}
