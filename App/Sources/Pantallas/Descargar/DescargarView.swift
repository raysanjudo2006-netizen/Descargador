import QuickLook
import SwiftUI
import UIKit

/// Pantalla principal: pegar el enlace, analizarlo y descargar.
struct DescargarView: View {
    @EnvironmentObject private var estado: EstadoApp
    @EnvironmentObject private var gestor: GestorDescargas
    @Environment(\.scenePhase) private var fase
    @FocusState private var campoEnfocado: Bool
    @AppStorage("guardarEnFotos") private var guardarEnFotos = true
    @AppStorage("mantenerActivo") private var mantenerActivo = false

    /// Hay un enlace en el portapapeles que aún no hemos ofrecido.
    @State private var hayEnlaceCopiado = false
    /// `changeCount` del portapapeles cuando se detectó ese enlace.
    @State private var cambioDetectado = 0
    /// Archivo abierto con Vista Rápida.
    @State private var vistaPrevia: URL?

    var body: some View {
        NavigationStack {
            Form {
                if gestor.fase != .inactiva {
                    Section("Descarga") {
                        TarjetaDescarga(gestor: gestor, vistaPrevia: $vistaPrevia)
                    }
                }

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
                        resultadoAnalisis
                        if let calidad = estado.calidadSolicitada {
                            LabeledContent("Calidad pedida", value: calidad.titulo)
                        }
                    }
                    if case .listo(let info) = estado.analisis {
                        ListaCalidades(info: info, calidadPedida: estado.calidadSolicitada,
                                       bloqueado: gestor.ocupado) { opcion in
                            descargar(opcion, de: info)
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Descargar")
            .animation(.default, value: hayEnlaceCopiado)
            .animation(.default, value: estado.enlaceAnalizado)
            .animation(.default, value: estado.analisis)
            .animation(.default, value: gestor.ocupado)
        }
        .quickLookPreview($vistaPrevia)
        .onAppear(perform: comprobarPortapapeles)
        .onChange(of: fase) { nueva in
            if nueva == .active { comprobarPortapapeles() }
        }
        .onChange(of: estado.analisis) { nuevo in
            // Si Atajos o descargador://…&calidad=… pidió una calidad, se descarga sola.
            if case .listo(let info) = nuevo, let calidad = estado.calidadSolicitada,
               let opcion = info.opcion(calidad), opcion.disponible {
                descargar(opcion, de: info)
            }
        }
    }

    private func descargar(_ opcion: OpcionCalidad, de info: InfoVideo) {
        guard let url = estado.enlaceAnalizado, !gestor.ocupado else { return }
        campoEnfocado = false
        gestor.iniciar(info: info, opcion: opcion, url: url,
                       guardarEnFotos: guardarEnFotos, mantenerActivo: mantenerActivo)
    }

    // MARK: - Secciones

    /// Fila según el estado del análisis con yt-dlp.
    @ViewBuilder
    private var resultadoAnalisis: some View {
        switch estado.analisis {
        case .inactivo:
            EmptyView()
        case .analizando:
            HStack(spacing: 12) {
                ProgressView()
                Text("Analizando con yt-dlp…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("analizando")
        case .listo(let info):
            TarjetaVideo(info: info)
        case .fallo(let mensaje):
            VStack(alignment: .leading, spacing: 8) {
                Label(mensaje, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("Reintentar") { estado.reintentar() }
                    .buttonStyle(.borderless)
            }
            .accessibilityIdentifier("falloAnalisis")
        }
    }

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

    /// Mira si hay un enlace copiado SIN leerlo (no salta el aviso de "pegar desde otra app").
    private func comprobarPortapapeles() {
        let portapapeles = UIPasteboard.general
        let cambio = portapapeles.changeCount
        guard cambio != Portapapeles.ultimoCambioVisto, portapapeles.hasStrings || portapapeles.hasURLs else {
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
        Portapapeles.marcarVisto(hayEnlaceCopiado ? cambioDetectado : UIPasteboard.general.changeCount)
        hayEnlaceCopiado = false
    }
}
