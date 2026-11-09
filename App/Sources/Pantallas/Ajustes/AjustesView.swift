import SwiftUI

/// Ajustes de la app: apariencia, motor de descarga y datos de la compilación.
struct AjustesView: View {
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema
    @State private var copiado = false
    @State private var versiones: VersionesMotor?
    @State private var errorMotor: String?

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
                    LabeledContent("Python", value: versiones?.python ?? textoPendiente)
                    LabeledContent("yt-dlp", value: versiones?.ytDlp ?? textoPendiente)
                        .accessibilityIdentifier("versionYtDlp")
                    LabeledContent("yt-dlp-ejs", value: versiones?.ytDlpEjs ?? textoPendiente)
                } header: {
                    Text("Motor de descarga")
                } footer: {
                    if let errorMotor {
                        Text(errorMotor).foregroundStyle(.red)
                    } else {
                        Text("Actualizar yt-dlp desde aquí llega en la Etapa 5.")
                    }
                }

                Section {
                    LabeledContent("Versión", value: "\(InfoBuild.version) (build \(InfoBuild.build))")
                    LabeledContent("Commit", value: InfoBuild.commit)
                    LabeledContent("Sistema", value: InfoBuild.sistema)
                    LabeledContent("Modelo", value: InfoBuild.modelo)
                    Button {
                        Portapapeles.copiar(InfoBuild.resumen)
                        copiado = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiado = false }
                    } label: {
                        Label(copiado ? "Copiado" : "Copiar información",
                              systemImage: copiado ? "checkmark" : "doc.on.doc")
                    }
                } header: {
                    Text("Acerca de")
                } footer: {
                    Text("Uso personal. La firma gratuita caduca a los 7 días: vuelve a instalarla con iloader o renuévala en SideStore.")
                }
            }
            .navigationTitle("Ajustes")
            .task { await cargarVersiones() }
        }
    }

    private var textoPendiente: String {
        errorMotor == nil ? "Cargando…" : "—"
    }

    /// Pregunta a Python sus versiones (la primera vez arranca el intérprete).
    private func cargarVersiones() async {
        guard versiones == nil else { return }
        do {
            versiones = try await MotorPython.compartido.version()
            errorMotor = nil
        } catch {
            errorMotor = (error as? ErrorMotor)?.mensajeUsuario ?? error.localizedDescription
        }
    }
}
