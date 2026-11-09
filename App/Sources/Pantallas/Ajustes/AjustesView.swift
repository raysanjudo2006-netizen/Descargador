import SwiftUI

/// Ajustes de la app: descargas, apariencia, motor de descarga y datos de la compilación.
struct AjustesView: View {
    @EnvironmentObject private var gestor: GestorDescargas
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema
    @AppStorage("guardarEnFotos") private var guardarEnFotos = true
    @AppStorage("mantenerActivo") private var mantenerActivo = false
    @State private var copiado = false
    @State private var versiones: VersionesMotor?
    @State private var errorMotor: String?
    @State private var espacioUsado: Int64?
    @State private var confirmarVaciado = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Guardar videos en Fotos", isOn: $guardarEnFotos)
                    Toggle("Mantener activo en segundo plano", isOn: $mantenerActivo)
                        .accessibilityIdentifier("interruptorMantenerActivo")
                    Button(role: .destructive) {
                        confirmarVaciado = true
                    } label: {
                        LabeledContent("Vaciar descargas", value: espacioUsado.map(Formato.bytes) ?? "…")
                    }
                    .disabled(gestor.ocupado)
                } header: {
                    Text("Descargas")
                } footer: {
                    Text("«Mantener activo» reproduce silencio mientras descarga para que iOS no pause la app al salir de ella; gasta algo más de batería. Vaciar no borra lo guardado en Fotos.")
                }
                .confirmationDialog("¿Borrar las descargas guardadas en la app?", isPresented: $confirmarVaciado,
                                    titleVisibility: .visible) {
                    Button("Vaciar descargas", role: .destructive) {
                        Guardado.vaciar()
                        Task { await calcularEspacio() }
                    }
                }

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
            .task {
                await calcularEspacio()
                await cargarVersiones()
            }
        }
    }

    /// Calcula el espacio de las descargas fuera del hilo principal.
    private func calcularEspacio() async {
        espacioUsado = await Task.detached(priority: .utility) { Guardado.espacioUsado() }.value
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
