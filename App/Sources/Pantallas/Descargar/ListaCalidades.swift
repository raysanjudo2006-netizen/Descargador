import SwiftUI

/// Calidades disponibles con su tamaño aproximado. Tocar una empieza la descarga.
struct ListaCalidades: View {
    let info: InfoVideo
    let calidadPedida: Calidad?
    /// Hay otra descarga en marcha.
    let bloqueado: Bool
    let alElegir: (OpcionCalidad) -> Void

    var body: some View {
        Section {
            ForEach(info.opciones) { opcion in
                Button {
                    alElegir(opcion)
                } label: {
                    FilaCalidad(opcion: opcion, pedida: opcion.tipo != nil && opcion.tipo == calidadPedida)
                }
                .disabled(!opcion.disponible || bloqueado)
                .accessibilityIdentifier("calidad-\(opcion.calidad)")
            }
        } header: {
            Text("Calidad")
        } footer: {
            Text(bloqueado ? "Espera a que termine la descarga actual." : "Toca una calidad para descargarla.")
        }
    }
}

private struct FilaCalidad: View {
    let opcion: OpcionCalidad
    let pedida: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: opcion.tipo == .audio ? "music.note" : "film")
                .foregroundStyle(.tint)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(opcion.tipo?.titulo ?? opcion.calidad)
                    .foregroundStyle(.primary)
                if let detalle {
                    Text(detalle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text(textoTamano)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            if pedida {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Calidad pedida")
            }
        }
        .opacity(opcion.disponible ? 1 : 0.45)
        .accessibilityElement(children: .combine)
    }

    private var textoTamano: String {
        guard opcion.disponible else { return "No disponible" }
        return opcion.tamanoTexto ?? "Tamaño desconocido"
    }

    /// Resolución real, si hay que unir video y audio, etc.
    private var detalle: String? {
        guard opcion.disponible else { return nil }
        var partes: [String] = []
        if let resolucion = opcion.resolucion, opcion.tipo != .audio {
            partes.append("\(resolucion)p")
        }
        if opcion.unir { partes.append("video + audio") }
        if opcion.extraerAudio { partes.append("se extrae del video") }
        if let protocolo = opcion.protocolo, protocolo.hasPrefix("m3u8") { partes.append("HLS") }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}
