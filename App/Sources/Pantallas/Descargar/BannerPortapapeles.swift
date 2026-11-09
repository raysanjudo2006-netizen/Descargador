import SwiftUI

/// Aviso "Tienes un enlace copiado" que aparece al volver a la app.
///
/// "Usar" es un `PasteButton`: el sistema lo considera un permiso explícito, así que
/// iOS no muestra la alerta de "¿Permitir pegar?".
struct BannerPortapapeles: View {
    let alUsar: @MainActor (String) -> Void
    let alDescartar: @MainActor () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tienes un enlace copiado")
                    .font(.headline)
                Text("Pégalo para analizarlo.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            PasteButton(payloadType: String.self) { textos in
                guard let texto = textos.first else { return }
                Task { @MainActor in alUsar(texto) }
            }
            .labelStyle(.iconOnly)
            .accessibilityIdentifier("botonUsarPortapapeles")
            Button(action: alDescartar) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Descartar")
            .accessibilityIdentifier("botonDescartarPortapapeles")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("bannerPortapapeles")
    }
}
