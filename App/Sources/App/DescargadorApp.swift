import SwiftUI

/// Punto de entrada de la app (versión provisional de la Tarea 1; la Tarea 3 monta las pestañas).
@main
struct DescargadorApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 12) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.tint)
                Text("Descargador")
                    .font(.largeTitle.bold())
                Text(InfoBuild.resumen)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
