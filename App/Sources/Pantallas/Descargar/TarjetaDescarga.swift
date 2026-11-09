import SwiftUI
import UIKit

/// Progreso real de la descarga en curso y, al terminar, Compartir / Abrir / Fotos.
struct TarjetaDescarga: View {
    @ObservedObject var gestor: GestorDescargas
    /// Archivo que se abre con Vista Rápida.
    @Binding var vistaPrevia: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(gestor.titulo ?? "Descarga")
                    .font(.headline)
                    .lineLimit(2)
                Spacer(minLength: 8)
                if let calidad = gestor.calidad {
                    Text(calidad.titulo)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(.tint)
                }
            }
            contenido
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tarjetaDescarga")
    }

    @ViewBuilder
    private var contenido: some View {
        switch gestor.fase {
        case .inactiva:
            EmptyView()

        case .preparando:
            HStack(spacing: 10) {
                ProgressView()
                Text("Preparando la descarga…").foregroundStyle(.secondary)
            }
            botonCancelar

        case .descargando(let progreso):
            if let fraccion = progreso.fraccion {
                ProgressView(value: fraccion)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Descargando…").foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(progreso.fraccion.map(Formato.porcentaje) ?? "—")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(textoBytes(progreso))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .monospacedDigit()
            if let detalle = textoDetalle(progreso) {
                Text(detalle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            botonCancelar

        case .procesando(let nombre, let valor):
            ProgressView(value: valor) {
                Text(nombre).font(.subheadline)
            }
            botonCancelar

        case .terminada(let resultado):
            Label(textoTerminada(resultado), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let aviso = resultado.avisoFotos {
                Text(aviso)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 16) {
                ShareLink(item: resultado.archivo) {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                Button {
                    vistaPrevia = resultado.archivo
                } label: {
                    Label("Abrir", systemImage: resultado.esAudio ? "play.circle" : "play.rectangle")
                }
                if resultado.enFotos, let fotos = URL(string: "photos-redirect://") {
                    Button {
                        UIApplication.shared.open(fotos)
                    } label: {
                        Label("Fotos", systemImage: "photo.on.rectangle")
                    }
                }
                Spacer(minLength: 0)
                botonCerrar
            }
            .buttonStyle(.borderless)
            .labelStyle(.titleAndIcon)

        case .fallida(let mensaje):
            Label(mensaje, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityIdentifier("falloDescarga")
            botonesReintentar

        case .cancelada:
            Label("Descarga cancelada", systemImage: "xmark.circle")
                .foregroundStyle(.secondary)
            botonesReintentar
        }
    }

    private var botonCancelar: some View {
        Button(role: .destructive) {
            gestor.cancelar()
        } label: {
            Label("Cancelar descarga", systemImage: "xmark.circle")
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("botonCancelar")
    }

    private var botonCerrar: some View {
        Button {
            gestor.cerrar()
        } label: {
            Image(systemName: "xmark")
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Cerrar")
    }

    private var botonesReintentar: some View {
        HStack {
            Button("Reintentar") { gestor.reintentar() }
            Spacer()
            botonCerrar
        }
        .buttonStyle(.borderless)
    }

    // MARK: - Textos

    /// "12,3 MB de 50 MB" o "12,3 MB descargados".
    private func textoBytes(_ progreso: ProgresoTotal) -> String {
        let bajado = Formato.bytes(progreso.descargado)
        guard let total = progreso.total else { return "\(bajado) descargados" }
        return "\(bajado) de \(progreso.aproximado ? "≈ " : "")\(Formato.bytes(total))"
    }

    /// "1,2 MB/s · quedan 0:32 · parte 2 de 2 (audio)".
    private func textoDetalle(_ progreso: ProgresoTotal) -> String? {
        var partes: [String] = []
        if let velocidad = progreso.velocidad, velocidad > 0 { partes.append(Formato.velocidad(velocidad)) }
        if let eta = progreso.eta { partes.append("quedan \(Formato.tiempo(eta))") }
        if progreso.partes > 1, let parte = progreso.parte {
            partes.append("parte \(progreso.numeroParte) de \(progreso.partes) (\(parte))")
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    private func textoTerminada(_ resultado: ResultadoFinal) -> String {
        if resultado.esAudio { return "Audio guardado en Archivos" }
        return resultado.enFotos ? "Guardado en Fotos y en Archivos" : "Guardado en Archivos"
    }
}
