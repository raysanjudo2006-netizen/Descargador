import SwiftUI
import UIKit

/// Ajustes de la app. En esta etapa: apariencia y datos de la compilación.
struct AjustesView: View {
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema
    @State private var copiado = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apariencia") {
                    Picker("Tema", selection: $apariencia) {
                        ForEach(Apariencia.allCases) { opcion in
                            Text(opcion.titulo).tag(opcion)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("selectorApariencia")
                }

                Section {
                    LabeledContent("Python", value: "Pendiente")
                    LabeledContent("yt-dlp", value: "Pendiente")
                } header: {
                    Text("Motor de descarga")
                } footer: {
                    Text("Python y yt-dlp se añaden en la Etapa 2.")
                }

                Section {
                    LabeledContent("Versión", value: "\(InfoBuild.version) (build \(InfoBuild.build))")
                    LabeledContent("Commit", value: InfoBuild.commit)
                    LabeledContent("Sistema", value: InfoBuild.sistema)
                    LabeledContent("Modelo", value: InfoBuild.modelo)
                    Button {
                        UIPasteboard.general.string = InfoBuild.resumen
                        copiado = true
                    } label: {
                        Label(copiado ? "Copiado" : "Copiar información",
                              systemImage: copiado ? "checkmark" : "doc.on.doc")
                    }
                } header: {
                    Text("Acerca de")
                } footer: {
                    Text("Uso personal. La firma gratuita caduca a los 7 días: renuévala desde SideStore.")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}
