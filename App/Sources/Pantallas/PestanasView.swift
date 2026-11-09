import SwiftUI

/// Barra de pestañas con las cuatro secciones de la app.
struct PestanasView: View {
    @EnvironmentObject private var estado: EstadoApp

    var body: some View {
        TabView(selection: $estado.pestana) {
            DescargarView()
                .tabItem { Label("Descargar", systemImage: "arrow.down.circle") }
                .tag(Pestana.descargar)
            HistorialView()
                .tabItem { Label("Historial", systemImage: "clock") }
                .tag(Pestana.historial)
            AjustesView()
                .tabItem { Label("Ajustes", systemImage: "gearshape") }
                .tag(Pestana.ajustes)
            RegistroView()
                .tabItem { Label("Registro", systemImage: "list.bullet.rectangle") }
                .tag(Pestana.registro)
        }
    }
}
