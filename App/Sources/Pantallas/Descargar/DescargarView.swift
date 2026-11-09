import SwiftUI
import UIKit

/// Pantalla principal: pegar el enlace, analizarlo y (desde la Etapa 3) descargar.
struct DescargarView: View {
    @EnvironmentObject private var estado: EstadoApp
    @Environment(\.scenePhase) private var fase
    @FocusState private var campoEnfocado: Bool

    /// Hay un enlace en el portapapeles que aún no hemos ofrecido.
    @State private var hayEnlaceCopiado = false
    /// `changeCount` del portapapeles cuando se detectó ese enlace.
    @State private var cambioDetectado = 0

    var body: some View {
        NavigationStack {
            Form {
                if hayEnlaceCopiado {
                    Section {
                        BannerPortapapeles(
                            alUsar: { texto in
                                marcarPortapapelesVisto()
                                estado.usarTextoPegado(texto)
                            },
                            alDescartar: marcarPortapapelesVisto
                        )
                    }
                }

                seccionEnlace

                Section {
                    Button {
                        campoEnfocado = false
                        estado.analizar()
                    } label: {
                        Label("Analizar enlace", systemImage: "magnifyingglass")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(estado.textoEnlace.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("botonAnalizar")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if let url = estado.enlaceAnalizado {
                    Section("Video") {
                        TarjetaEnlace(url: url)
                        if let calidad = estado.calidadSolicitada {
                            LabeledContent("Calidad pedida", value: calidad.titulo)
                        }
                        Text("En la Etapa 2 aquí aparecerán la miniatura, la duración y los botones de calidad con su tamaño.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Descargar")
            .animation(.default, value: hayEnlaceCopiado)
            .animation(.default, value: estado.enlaceAnalizado)
        }
        .onAppear(perform: comprobarPortapapeles)
        .onChange(of: fase) { nueva in
            if nueva == .active { comprobarPortapapeles() }
        }
    }

    // MARK: - Secciones

    private var seccionEnlace: some View {
        Section {
            HStack(spacing: 8) {
                TextField("Enlace del video", text: $estado.textoEnlace)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($campoEnfocado)
                    .onSubmit { estado.analizar() }
                    .accessibilityIdentifier("campoEnlace")
                if !estado.textoEnlace.isEmpty {
                    Button {
                        estado.textoEnlace = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Borrar enlace")
                }
            }
            PasteButton(payloadType: String.self) { textos in
                guard let texto = textos.first else { return }
                Task { @MainActor in
                    marcarPortapapelesVisto()
                    estado.usarTextoPegado(texto)
                }
            }
            .accessibilityIdentifier("botonPegar")
        } header: {
            Text("Enlace")
        } footer: {
            if let mensaje = estado.mensajeError {
                Label(mensaje, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("mensajeError")
            } else {
                Text("YouTube, Instagram, TikTok, X, Facebook y muchas webs más.")
            }
        }
    }

    // MARK: - Portapapeles

    /// Clave en UserDefaults con el último `changeCount` ya ofrecido (los UI tests la fijan al lanzar).
    private static let claveUltimoCambio = "ultimoCambioPortapapeles"

    private var ultimoCambioVisto: Int {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: Self.claveUltimoCambio) == nil ? -1 : defaults.integer(forKey: Self.claveUltimoCambio)
    }

    /// Mira si hay un enlace copiado SIN leerlo (no salta el aviso de "pegar desde otra app").
    private func comprobarPortapapeles() {
        let portapapeles = UIPasteboard.general
        let cambio = portapapeles.changeCount
        guard cambio != ultimoCambioVisto, portapapeles.hasStrings || portapapeles.hasURLs else {
            hayEnlaceCopiado = false
            return
        }
        portapapeles.detectPatterns(for: [.probableWebURL]) { resultado in
            let esEnlace = (try? resultado.get())?.contains(.probableWebURL) ?? false
            DispatchQueue.main.async {
                cambioDetectado = cambio
                hayEnlaceCopiado = esEnlace
            }
        }
    }

    /// No volver a ofrecer el contenido actual del portapapeles.
    private func marcarPortapapelesVisto() {
        let cambio = hayEnlaceCopiado ? cambioDetectado : UIPasteboard.general.changeCount
        UserDefaults.standard.set(cambio, forKey: Self.claveUltimoCambio)
        hayEnlaceCopiado = false
    }
}
