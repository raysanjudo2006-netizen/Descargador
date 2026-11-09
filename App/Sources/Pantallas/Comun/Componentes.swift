import SwiftUI

/// Estado vacío: usa `ContentUnavailableView` nativo en iOS 17+ y una versión equivalente en iOS 16.
struct VistaVacia: View {
    let titulo: String
    let simbolo: String
    let descripcion: String

    var body: some View {
        if #available(iOS 17.0, *) {
            ContentUnavailableView {
                Label(titulo, systemImage: simbolo)
            } description: {
                Text(descripcion)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: simbolo)
                    .font(.largeTitle)
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(titulo)
                    .font(.title2.bold())
                Text(descripcion)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Cuadrado redondeado con el símbolo de la plataforma, en el color de acento.
struct IconoPlataforma: View {
    let plataforma: Plataforma
    /// Crece con el tamaño de texto del usuario (Dynamic Type).
    @ScaledMetric(relativeTo: .headline) private var lado: CGFloat = 40

    var body: some View {
        Image(systemName: plataforma.simbolo)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(width: lado, height: lado)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: lado * 0.25, style: .continuous))
            .accessibilityHidden(true)
    }
}
