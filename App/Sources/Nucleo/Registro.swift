import Combine
import Foundation

/// Gravedad de una entrada del registro.
enum NivelRegistro: String, Codable, CaseIterable {
    case depuracion, info, aviso, error

    /// Etiqueta corta que aparece en el texto copiado.
    var etiqueta: String {
        switch self {
        case .depuracion: return "DEBUG"
        case .info: return "INFO"
        case .aviso: return "AVISO"
        case .error: return "ERROR"
        }
    }
}

/// Una línea del registro.
struct EntradaRegistro: Codable, Identifiable, Equatable {
    let id: UUID
    let fecha: Date
    let nivel: NivelRegistro
    let categoria: String
    let mensaje: String

    /// Formato de texto: "2026-11-09 10:00:00.123 [INFO] [app] mensaje".
    var lineaTexto: String {
        "\(Self.textoFecha(fecha)) [\(nivel.etiqueta)] [\(categoria)] \(mensaje)"
    }

    /// Fecha con milisegundos, p. ej. "2026-11-09 10:00:00.123".
    static func textoFecha(_ fecha: Date) -> String {
        formatoFecha.string(from: fecha)
    }

    private static let formatoFecha: DateFormatter = {
        let formato = DateFormatter()
        formato.locale = Locale(identifier: "en_US_POSIX")
        formato.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formato
    }()
}

/// Registro interno de la app: lo que se ve (y se copia) en la pestaña "Registro".
///
/// - Se puede llamar desde cualquier hilo (más adelante, Python escribirá aquí).
/// - Se guarda en disco como JSON Lines (una entrada por línea) para sobrevivir a cierres
///   inesperados; al arrancar se recupera lo anterior, ignorando líneas dañadas.
/// - Conserva las últimas `maxEntradas` entradas.
final class Registro: ObservableObject {
    /// Registro de la app, en Caches/registro.jsonl.
    static let compartido: Registro = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return Registro(archivo: caches.appendingPathComponent("registro.jsonl"))
    }()

    /// Entradas en memoria; solo se modifican en el hilo principal.
    @Published private(set) var entradas: [EntradaRegistro] = []

    private let archivo: URL
    private let maxEntradas: Int
    /// Líneas de más que se permiten en el archivo antes de recortarlo (evita reescribir en cada entrada).
    private let holgura: Int
    /// Cola serie para todo lo que toca el disco.
    private let cola = DispatchQueue(label: "com.personal.descargador.registro")
    /// Líneas actuales del archivo. Solo se usa dentro de `cola`.
    private var lineasEnArchivo = 0

    private static let iso: ISO8601DateFormatter = {
        let formato = ISO8601DateFormatter()
        formato.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formato
    }()

    private let codificador: JSONEncoder = {
        let codificador = JSONEncoder()
        codificador.outputFormatting = [.withoutEscapingSlashes]
        codificador.dateEncodingStrategy = .custom { fecha, encoder in
            var contenedor = encoder.singleValueContainer()
            try contenedor.encode(Registro.iso.string(from: fecha))
        }
        return codificador
    }()

    private let decodificador: JSONDecoder = {
        let decodificador = JSONDecoder()
        decodificador.dateDecodingStrategy = .custom { decoder in
            let contenedor = try decoder.singleValueContainer()
            let texto = try contenedor.decode(String.self)
            guard let fecha = Registro.iso.date(from: texto) else {
                throw DecodingError.dataCorruptedError(in: contenedor, debugDescription: "Fecha inválida: \(texto)")
            }
            return fecha
        }
        return decodificador
    }()

    init(archivo: URL, maxEntradas: Int = 2000) {
        self.archivo = archivo
        self.maxEntradas = max(1, maxEntradas)
        self.holgura = max(maxEntradas / 4, 2)

        let leido = Self.leer(archivo, con: decodificador)
        lineasEnArchivo = leido.lineas
        entradas = Array(leido.entradas.suffix(self.maxEntradas))

        // Si la app se cerró a mitad de una escritura, la última línea quedó sin salto:
        // lo añadimos para que la siguiente entrada no se pegue a ella.
        if !leido.terminaEnSalto {
            cola.async { [weak self] in self?.anadirAlArchivo(Data([0x0A])) }
        }
    }

    // MARK: - Escribir

    /// Añade una entrada. Seguro desde cualquier hilo.
    func registrar(_ nivel: NivelRegistro, _ mensaje: String, categoria: String = "app") {
        let entrada = EntradaRegistro(id: UUID(), fecha: Date(), nivel: nivel, categoria: categoria, mensaje: mensaje)
        #if DEBUG
        print(entrada.lineaTexto)
        #endif
        cola.async { [weak self] in self?.guardar(entrada) }
        if Thread.isMainThread {
            agregarEnMemoria(entrada)
        } else {
            DispatchQueue.main.async { [weak self] in self?.agregarEnMemoria(entrada) }
        }
    }

    func depurar(_ mensaje: String, categoria: String = "app") { registrar(.depuracion, mensaje, categoria: categoria) }
    func info(_ mensaje: String, categoria: String = "app") { registrar(.info, mensaje, categoria: categoria) }
    func aviso(_ mensaje: String, categoria: String = "app") { registrar(.aviso, mensaje, categoria: categoria) }
    func error(_ mensaje: String, categoria: String = "app") { registrar(.error, mensaje, categoria: categoria) }

    /// Borra todo el registro (memoria y disco). Llamar desde el hilo principal.
    func limpiar() {
        entradas.removeAll()
        cola.async { [weak self] in
            guard let self = self else { return }
            try? Data().write(to: self.archivo)
            self.lineasEnArchivo = 0
        }
    }

    /// Espera a que terminen las escrituras pendientes en disco (útil en tests).
    func esperarEscrituras() {
        cola.sync {}
    }

    // MARK: - Leer

    /// Texto completo para copiar o compartir: cabecera con build y dispositivo + todas las líneas.
    func textoCompleto() -> String {
        Self.texto(de: entradas)
    }

    /// Formatea una lista de entradas con la cabecera. Seguro fuera del hilo principal.
    static func texto(de entradas: [EntradaRegistro]) -> String {
        var lineas = [
            "=== Registro de \(InfoBuild.resumen) ===",
            "Copiado: \(EntradaRegistro.textoFecha(Date()))",
            "",
        ]
        lineas.append(contentsOf: entradas.map(\.lineaTexto))
        return lineas.joined(separator: "\n")
    }

    // MARK: - Interno

    private func agregarEnMemoria(_ entrada: EntradaRegistro) {
        entradas.append(entrada)
        if entradas.count > maxEntradas {
            entradas.removeFirst(entradas.count - maxEntradas)
        }
    }

    /// Escribe una entrada al final del archivo. Solo dentro de `cola`.
    private func guardar(_ entrada: EntradaRegistro) {
        guard var datos = try? codificador.encode(entrada) else { return }
        datos.append(0x0A)
        anadirAlArchivo(datos)
        lineasEnArchivo += 1
        if lineasEnArchivo > maxEntradas + holgura {
            recortarArchivo()
        }
    }

    /// Añade bytes al final del archivo, creándolo si no existe. Solo dentro de `cola`.
    private func anadirAlArchivo(_ datos: Data) {
        if let manejador = try? FileHandle(forWritingTo: archivo) {
            defer { try? manejador.close() }
            _ = try? manejador.seekToEnd()
            try? manejador.write(contentsOf: datos)
        } else {
            try? FileManager.default.createDirectory(
                at: archivo.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? datos.write(to: archivo)
        }
    }

    /// Reescribe el archivo dejando solo las últimas `maxEntradas` válidas. Solo dentro de `cola`.
    private func recortarArchivo() {
        let ultimas = Self.leer(archivo, con: decodificador).entradas.suffix(maxEntradas)
        var datos = Data()
        for entrada in ultimas {
            if let linea = try? codificador.encode(entrada) {
                datos.append(linea)
                datos.append(0x0A)
            }
        }
        try? datos.write(to: archivo, options: .atomic)
        lineasEnArchivo = ultimas.count
    }

    /// Lee el archivo: entradas válidas, número de líneas (válidas o no) y si acaba en salto de línea.
    private static func leer(_ archivo: URL, con decodificador: JSONDecoder)
        -> (entradas: [EntradaRegistro], lineas: Int, terminaEnSalto: Bool) {
        guard let datos = try? Data(contentsOf: archivo), !datos.isEmpty else {
            return ([], 0, true)
        }
        let lineas = datos.split(separator: 0x0A, omittingEmptySubsequences: true)
        let entradas = lineas.compactMap { try? decodificador.decode(EntradaRegistro.self, from: Data($0)) }
        return (entradas, lineas.count, datos.last == 0x0A)
    }
}
