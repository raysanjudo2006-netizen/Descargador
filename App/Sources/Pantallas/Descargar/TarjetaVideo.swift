import SwiftUI

/// Miniatura, título, autor y duración del video analizado.
struct TarjetaVideo: View {
    let info: InfoVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = info.urlMiniatura {
                // Marco 16:9 fijo; la imagen lo llena y se recorta.
                Color.clear
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        AsyncImage(url: url) { fase in
                            switch fase {
                            case .success(let imagen):
                                imagen.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "photo")
                                    .font(.title)
                                    .foregroundStyle(.secondary)
                            default:
                                ProgressView()
                            }
                        }
                    }
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .accessibilityHidden(true)
            }
            Text(info.titulo)
                .font(.headline)
                .lineLimit(3)
                .accessibilityIdentifier("tituloVideo")
            let detalles = [info.autor, info.duracionTexto].compactMap { $0 }
            if !detalles.isEmpty {
                Text(detalles.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
