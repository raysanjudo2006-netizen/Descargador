import SwiftUI
import UIKit

/// Registro interno: lo que pasa por dentro de la app, para copiarlo y pegármelo si algo falla.
struct RegistroView: View {
    @EnvironmentObject private var registro: Registro
    @State private var confirmarBorrado = false
    @State private var copiado = false

    var body: some View {
        NavigationStack {
            Group {
                if registro.entradas.isEmpty {
                    VistaVacia(
                        titulo: "Registro vacío",
                        simbolo: "list.bullet.rectangle",
                        descripcion: "Aquí se anota lo que hace la app. Si algo falla, cópialo y pégalo en el chat."
                    )
                } else {
                    lista
                }
            }
            .navigationTitle("Registro")
            .toolbar { barra }
            .confirmationDialog("¿Borrar todo el registro?", isPresented: $confirmarBorrado, titleVisibility: .visible) {
                Button("Borrar registro", role: .destructive) { registro.limpiar() }
            }
        }
    }

    private var lista: some View {
        ScrollViewReader { proxy in
            List(registro.entradas) { entrada in
                FilaRegistro(entrada: entrada)
                    .id(entrada.id)
            }
            .listStyle(.plain)
            .accessibilityIdentifier("listaRegistro")
            .onAppear { irAlFinal(proxy) }
            .onChange(of: registro.entradas.count) { _ in irAlFinal(proxy) }
        }
    }

    @ToolbarContentBuilder
    private var barra: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Button {
                UIPasteboard.general.string = registro.textoCompleto()
                copiado = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiado = false }
            } label: {
                Label(copiado ? "Copiado" : "Copiar", systemImage: copiado ? "checkmark" : "doc.on.doc")
            }
            .disabled(registro.entradas.isEmpty)
            .accessibilityIdentifier("botonCopiarRegistro")

            ShareLink(item: registro.textoCompleto()) {
                Label("Compartir", systemImage: "square.and.arrow.up")
            }
            .disabled(registro.entradas.isEmpty)

            Button(role: .destructive) {
                confirmarBorrado = true
            } label: {
                Label("Borrar", systemImage: "trash")
            }
            .disabled(registro.entradas.isEmpty)
        }
    }

    private func irAlFinal(_ proxy: ScrollViewProxy) {
        if let ultima = registro.entradas.last {
            proxy.scrollTo(ultima.id, anchor: .bottom)
        }
    }
}

/// Una entrada: hora, nivel y categoría arriba; el mensaje (seleccionable) debajo.
private struct FilaRegistro: View {
    let entrada: EntradaRegistro

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entrada.fecha.formatted(date: .omitted, time: .standard))
                    .foregroundStyle(.secondary)
                Text(entrada.nivel.etiqueta)
                    .fontWeight(.semibold)
                    .foregroundStyle(color)
                Text(entrada.categoria)
                    .foregroundStyle(.secondary)
            }
            .font(.system(.caption2, design: .monospaced))
            Text(entrada.mensaje)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(entrada.nivel == .depuracion ? Color.secondary : Color.primary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch entrada.nivel {
        case .depuracion: return .secondary
        case .info: return .accentColor
        case .aviso: return .orange
        case .error: return .red
        }
    }
}
