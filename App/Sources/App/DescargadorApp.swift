import SwiftUI

/// Punto de entrada de la app.
///
/// Argumentos de lanzamiento que usan los UI tests (llegan por UserDefaults):
///   -pestanaInicial <descargar|historial|ajustes|registro>
///   -apariencia <sistema|claro|oscuro>
///   -ultimoCambioPortapapeles <número>
@main
struct DescargadorApp: App {
    @StateObject private var estado: EstadoApp
    @StateObject private var historial: HistorialStore
    @StateObject private var gestor: GestorDescargas
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema

    init() {
        let inicial = UserDefaults.standard.string(forKey: "pestanaInicial")
            .flatMap(Pestana.init(rawValue:)) ?? .descargar
        _estado = StateObject(wrappedValue: EstadoApp(pestanaInicial: inicial))
        let historial = HistorialStore()
        _historial = StateObject(wrappedValue: historial)
        _gestor = StateObject(wrappedValue: GestorDescargas(historial: historial))
        Registro.compartido.info("Inicio · \(InfoBuild.resumen)")
    }

    var body: some Scene {
        WindowGroup {
            PestanasView()
                .environmentObject(estado)
                .environmentObject(gestor)
                .environmentObject(historial)
                .environmentObject(Registro.compartido)
                .preferredColorScheme(apariencia.esquema)
                .onOpenURL { url in
                    // La extensión de Compartir también copia el enlace (por si iOS no abre la
                    // app): como ya llegó por aquí, que el aviso del portapapeles no lo repita.
                    Portapapeles.marcarVisto(UIPasteboard.general.changeCount)
                    estado.abrir(enlaceProfundo: url)
                }
        }
    }
}
