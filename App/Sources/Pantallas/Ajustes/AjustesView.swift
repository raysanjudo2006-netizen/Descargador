import SwiftUI
import UniformTypeIdentifiers

/// Ajustes de la app: descargas, cookies, motor de descarga, apariencia y datos de la compilación.
struct AjustesView: View {
    @EnvironmentObject private var gestor: GestorDescargas
    @EnvironmentObject private var historial: HistorialStore
    @StateObject private var actualizador = ActualizadorYtDlp()
    @AppStorage("apariencia") private var apariencia: Apariencia = .sistema
    @AppStorage("guardarEnFotos") private var guardarEnFotos = true
    @AppStorage("mantenerActivo") private var mantenerActivo = false
    /// "" = preguntar; si no, el rawValue de Calidad.
    @AppStorage("calidadPredeterminada") private var calidadPredeterminada = ""
    @State private var copiado = false
    @State private var versiones: VersionesMotor?
    @State private var errorMotor: String?
    @State private var espacioUsado: Int64?
    @State private var confirmarVaciado = false
    @State private var importandoCookies = false
    @State private var cookiesImportadas = Cookies.importadas
    @State private var mensajeCookies: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Calidad para Compartir y Atajos", selection: $calidadPredeterminada) {
                        Text("Preguntar").tag("")
                        ForEach(Calidad.allCases) { calidad in
                            Text(calidad.titulo).tag(calidad.rawValue)
                        }
                    }
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
                    Text("Con una calidad elegida, lo que llega por Compartir o Atajos se descarga solo (si no existe, la más cercana por debajo). «Mantener activo» reproduce silencio mientras descarga para que iOS no pause la app; gasta algo más de batería. Vaciar no borra lo guardado en Fotos.")
                }
                .confirmationDialog("¿Borrar las descargas guardadas en la app?", isPresented: $confirmarVaciado,
                                    titleVisibility: .visible) {
                    Button("Vaciar descargas", role: .destructive) {
                        Guardado.vaciar()
                        historial.vaciar()
                        Task { await calcularEspacio() }
                    }
                }


                Section {
                    LabeledContent("yt-dlp", value: textoYtDlp)
                        .accessibilityIdentifier("versionYtDlp")
                    filaActualizador
                    if actualizador.instalada != nil {
                        Button("Volver al yt-dlp incluido en la app", role: .destructive) {
                            actualizador.volverAIncluida()
                        }
                    }
                    LabeledContent("Python", value: versiones?.python ?? textoPendiente)
                    LabeledContent("yt-dlp-ejs", value: versiones?.ytDlpEjs ?? textoPendiente)
                } header: {
                    Text("Motor de descarga")
                } footer: {
                    if let errorMotor {
                        Text(errorMotor).foregroundStyle(.red)
                    } else {
                        Text("Si una web deja de funcionar, normalmente basta con actualizar yt-dlp. Se descarga de GitHub (unos 3 MB) y se usa al volver a abrir la app.")
                    }
                }

                Section {
                    LabeledContent("Cookies", value: cookiesImportadas ? "Importadas" : "Ninguna")
                    Button(cookiesImportadas ? "Reemplazar cookies.txt" : "Importar cookies.txt") {
                        importandoCookies = true
                    }
                    if cookiesImportadas {
                        Button("Borrar cookies", role: .destructive) {
                            Cookies.borrar()
                            cookiesImportadas = false
                            mensajeCookies = "Cookies borradas."
                        }
                    }
                } header: {
                    Text("Cookies (opcional)")
                } footer: {
                    Text(mensajeCookies ?? "Solo hacen falta si un video pide tu sesión: privado, con edad o «confirma que no eres un robot». Exporta cookies.txt desde el navegador del PC y pásalo al iPhone. Son como tu contraseña: no las compartas.")
                }
                .fileImporter(isPresented: $importandoCookies,
                              allowedContentTypes: [.plainText, .text, .data]) { resultado in
                    importarCookies(resultado)
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

    private func importarCookies(_ resultado: Result<URL, Error>) {
        do {
            let cantidad = try Cookies.importar(desde: resultado.get())
            cookiesImportadas = true
            mensajeCookies = "Importadas \(cantidad) cookies. Se usarán en los próximos análisis."
        } catch {
            mensajeCookies = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Calcula el espacio de las descargas fuera del hilo principal.
    private func calcularEspacio() async {
        espacioUsado = await Task.detached(priority: .utility) { Guardado.espacioUsado() }.value
    }

    private var textoPendiente: String {
        errorMotor == nil ? "Cargando…" : "—"
    }

    private var textoYtDlp: String {
        guard let versiones else { return textoPendiente }
        return versiones.ytDlpActualizado ? "\(versiones.ytDlp) (actualizado)" : versiones.ytDlp
    }

    /// Botón o estado de "Buscar actualización de yt-dlp".
    @ViewBuilder
    private var filaActualizador: some View {
        switch actualizador.estado {
        case .inactivo:
            Button("Buscar actualización de yt-dlp") { buscarActualizacion() }
                .disabled(versiones == nil)
        case .buscando:
            HStack(spacing: 10) {
                ProgressView()
                Text("Buscando en GitHub…").foregroundStyle(.secondary)
            }
        case .alDia(let version):
            Label("Tienes la última versión (\(version))", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .disponible(let version):
            Button {
                Task { await actualizador.instalar() }
            } label: {
                Label("Instalar yt-dlp \(version)", systemImage: "arrow.down.circle.fill")
            }
            .disabled(gestor.ocupado)
        case .descargando(let texto):
            HStack(spacing: 10) {
                ProgressView()
                Text(texto).foregroundStyle(.secondary)
            }
        case .instalada(let version):
            Label("yt-dlp \(version) listo. Cierra la app (desliza hacia arriba desde el selector de apps) y vuelve a abrirla para usarlo.",
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .error(let mensaje):
            VStack(alignment: .leading, spacing: 6) {
                Label(mensaje, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                Button("Reintentar") { buscarActualizacion() }
                    .buttonStyle(.borderless)
            }
        }
    }

    private func buscarActualizacion() {
        guard let actual = versiones?.ytDlp else { return }
        Task { await actualizador.buscar(versionActual: actual) }
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
