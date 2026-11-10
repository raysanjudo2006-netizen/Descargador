import QuickLook
import SwiftUI
import UIKit

/// Historial de descargas: tocar abre el archivo; deslizar o mantener pulsado para compartir o borrar.
struct HistorialView: View {
    @EnvironmentObject private var historial: HistorialStore
    @State private var vistaPrevia: URL?

    var body: some View {
        NavigationStack {
            Group {
                if historial.entradas.isEmpty {
                    VistaVacia(
                        titulo: "Sin descargas",
                        simbolo: "tray",
                        descripcion: "Los videos y audios que descargues aparecerán aquí para reproducirlos, compartirlos o borrarlos."
                    )
                } else {
                    List {
                        ForEach(historial.entradas) { entrada in
                            fila(entrada)
                        }
                    }
                    .listStyle(.plain)
                    .accessibilityIdentifier("listaHistorial")
                }
            }
            .navigationTitle("Historial")
        }
        .quickLookPreview($vistaPrevia)
    }

    private func fila(_ entrada: EntradaHistorial) -> some View {
        let existe = historial.existeArchivo(entrada)
        let archivo = historial.urlArchivo(entrada)
        return Button {
            if existe { vistaPrevia = archivo }
        } label: {
            FilaHistorial(entrada: entrada, miniatura: historial.urlMiniatura(entrada), existe: existe)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                historial.borrar(entrada)
            } label: {
                Label("Borrar", systemImage: "trash")
            }
        }
        .contextMenu {
            if existe {
                Button {
                    vistaPrevia = archivo
                } label: {
                    Label("Abrir", systemImage: entrada.esAudio ? "play.circle" : "play.rectangle")
                }
                ShareLink(item: archivo) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                historial.borrar(entrada)
            } label: {
                Label(existe ? "Borrar" : "Quitar del historial", systemImage: "trash")
            }
        }
    }
}

/// Miniatura, título y "Plataforma · tamaño · fecha".
private struct FilaHistorial: View {
    let entrada: EntradaHistorial
    let miniatura: URL?
    let existe: Bool
    @ScaledMetric(relativeTo: .subheadline) private var alto: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            imagen
                .frame(width: alto * 16 / 9, height: alto)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(entrada.titulo)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(detalle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !existe {
                    Text("El archivo ya no está en la app")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .opacity(existe ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var imagen: some View {
        if let miniatura, let foto = UIImage(contentsOfFile: miniatura.path) {
            Image(uiImage: foto)
                .resizable()
                .scaledToFill()
        } else {
            ZStack {
                Rectangle().fill(.quaternary)
                Image(systemName: entrada.esAudio ? "music.note" : entrada.plataforma.simbolo)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detalle: String {
        var partes = [entrada.plataforma.nombre]
        if entrada.bytes > 0 { partes.append(Formato.bytes(entrada.bytes)) }
        partes.append(entrada.fecha.formatted(.relative(presentation: .named)))
        return partes.joined(separator: " · ")
    }
}
