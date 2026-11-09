import SwiftUI

/// Fila con la plataforma detectada y el host del enlace.
struct TarjetaEnlace: View {
    let url: URL

    var body: some View {
        let plataforma = Plataforma.detectar(url)
        HStack(spacing: 12) {
            IconoPlataforma(plataforma: plataforma)
            VStack(alignment: .leading, spacing: 2) {
                Text(plataforma.nombre)
                    .font(.headline)
                    .accessibilityIdentifier("etiquetaPlataforma")
                Text(url.host ?? url.absoluteString)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tarjetaEnlace")
    }
}
