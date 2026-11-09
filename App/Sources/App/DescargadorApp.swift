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
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema

    init() {
        let inicial = UserDefaults.standard.string(forKey: "pestanaInicial")
            .flatMap(Pestana.init(rawValue:)) ?? .descargar
        _estado = StateObject(wrappedValue: EstadoApp(pestanaInicial: inicial))
        Registro.compartido.info("Inicio · \(InfoBuild.resumen)")
    }

    var body: some Scene {
        WindowGroup {
            PestanasView()
                .environmentObject(estado)
                .environmentObject(Registro.compartido)
                .preferredColorScheme(apariencia.esquema)
                .onOpenURL { url in
                    estado.abrir(enlaceProfundo: url)
                }
        }
    }
}
