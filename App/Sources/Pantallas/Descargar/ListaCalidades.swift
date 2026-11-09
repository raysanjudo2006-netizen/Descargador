import SwiftUI

/// Calidades disponibles con su tamaño aproximado (elegir y descargar llega en la Etapa 3).
struct ListaCalidades: View {
    let info: InfoVideo
    let calidadPedida: Calidad?

    var body: some View {
        Section {
            ForEach(info.opciones) { opcion in
                FilaCalidad(opcion: opcion, pedida: opcion.tipo != nil && opcion.tipo == calidadPedida)
            }
        } header: {
            Text("Calidad")
        } footer: {
            Text("Elegir una calidad y descargar llega en la Etapa 3.")
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
        .accessibilityIdentifier("calidad-\(opcion.calidad)")
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
