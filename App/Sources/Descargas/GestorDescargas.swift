import CryptoKit
import Foundation
import UIKit

/// Lleva la descarga en curso (una a la vez): yt-dlp → unir/preparar con AVFoundation →
/// guardar en Archivos y, si está activado, en Fotos.
@MainActor
final class GestorDescargas: ObservableObject {
    @Published private(set) var fase: FaseDescarga = .inactiva
    /// Título y calidad de la descarga actual o de la última terminada.
    @Published private(set) var titulo: String?
    @Published private(set) var calidad: Calidad?

    private let motor: MotorDescargas
    private let registro: Registro
    private let historial: HistorialStore?
    private let segundoPlano: SegundoPlano
    private let carpetaTemporal: URL
    private let permitirArchivos: Bool
    private let pedirPermisos: Bool
    private var tarea: Task<Void, Never>?
    private let cancelacion = BanderaCancelacion()
    private var acumulador = AcumuladorProgreso(partes: [], estimacionTotal: nil)
    /// Para "Reintentar".
    private var ultimaPeticion: (info: InfoVideo, opcion: OpcionCalidad, url: URL, fotos: Bool, activo: Bool)?

    init(motor: MotorDescargas = MotorPython.compartido,
         registro: Registro = .compartido,
         historial: HistorialStore? = nil,
         carpetaTemporal: URL = Guardado.carpetaTemporal,
         permitirArchivos: Bool = false,
         pedirPermisos: Bool = true) {
        self.motor = motor
        self.registro = registro
        self.historial = historial
        self.segundoPlano = SegundoPlano(registro: registro)
        self.carpetaTemporal = carpetaTemporal
        self.permitirArchivos = permitirArchivos
        self.pedirPermisos = pedirPermisos
    }

    /// Hay una descarga en marcha (no se puede empezar otra).
    var ocupado: Bool {
        switch fase {
        case .preparando, .descargando, .procesando: return true
        default: return false
        }
    }

    // MARK: - Acciones

    func iniciar(info: InfoVideo, opcion: OpcionCalidad, url: URL, guardarEnFotos: Bool, mantenerActivo: Bool) {
        guard !ocupado, opcion.disponible else { return }
        let partes = Self.partes(de: opcion)
        guard !partes.isEmpty else {
            fase = .fallida("Esta calidad no tiene formatos para descargar.")
            return
        }
        ultimaPeticion = (info, opcion, url, guardarEnFotos, mantenerActivo)
        cancelacion.reiniciar()
        titulo = info.titulo
        calidad = opcion.tipo
        acumulador = AcumuladorProgreso(partes: partes.map(\.parte), estimacionTotal: opcion.bytes)
        fase = .preparando
        registro.info("Descarga: \(info.titulo) · \(opcion.tipo?.titulo ?? opcion.calidad) · formatos \(partes.map(\.formato).joined(separator: "+"))",
                      categoria: "descarga")

        let carpeta = carpetaTemporal.appendingPathComponent(Self.nombreCarpeta(url: url, calidad: opcion.calidad), isDirectory: true)
        segundoPlano.comenzar(titulo: info.titulo, mantenerActivo: mantenerActivo)
        if pedirPermisos {
            Task { await Notificaciones.pedirPermiso() }
        }

        tarea = Task { [weak self] in
            await self?.ejecutar(info: info, opcion: opcion, url: url, partes: partes, carpeta: carpeta,
                                 guardarEnFotos: guardarEnFotos)
        }
    }

    func cancelar() {
        guard ocupado else { return }
        cancelacion.activar()
        MotorJavaScript.cancelarEvaluaciones()  // por si está resolviendo un desafío de YouTube
        tarea?.cancel()
        registro.info("Cancelando descarga…", categoria: "descarga")
    }

    func reintentar() {
        guard !ocupado, let p = ultimaPeticion else { return }
        iniciar(info: p.info, opcion: p.opcion, url: p.url, guardarEnFotos: p.fotos, mantenerActivo: p.activo)
    }

    /// Cierra la tarjeta de resultado.
    func cerrar() {
        guard !ocupado else { return }
        fase = .inactiva
    }

    /// Espera a que termine la descarga en curso (para los tests).
    func esperar() async {
        await tarea?.value
    }

    // MARK: - Proceso

    private func ejecutar(info: InfoVideo, opcion: OpcionCalidad, url: URL, partes: [ParteDescarga],
                          carpeta: URL, guardarEnFotos: Bool) async {
        defer { segundoPlano.terminar() }
        let cancelacion = self.cancelacion
        do {
            let resultado = try await motor.descargar(
                url: url, partes: partes, carpeta: carpeta, permitirArchivos: permitirArchivos,
                alProgreso: { [weak self] progreso in
                    Task { @MainActor in self?.recibir(progreso) }
                },
                cancelado: { cancelacion.activa })
            try comprobarCancelacion()
            let final = try await procesar(resultado, opcion: opcion, titulo: info.titulo,
                                         duracion: info.duracion, guardarEnFotos: guardarEnFotos)
            try? FileManager.default.removeItem(at: carpeta)
            fase = .terminada(final)
            registro.info("Terminada: \(final.archivo.lastPathComponent)\(final.enFotos ? " (también en Fotos)" : "")",
                          categoria: "descarga")
            await historial?.agregar(final, plataforma: Plataforma.detectar(url), calidad: opcion.tipo, enlace: url)
            if UIApplication.shared.applicationState != .active {
                Notificaciones.enviar(titulo: "Descarga terminada", cuerpo: final.titulo)
            }
        } catch {
            if cancelacion.activa || error is CancellationError || (error as? ErrorMotor)?.codigo == "cancelado" {
                try? FileManager.default.removeItem(at: carpeta)
                fase = .cancelada
                registro.info("Descarga cancelada", categoria: "descarga")
                return
            }
            let mensaje = (error as? ErrorMotor)?.mensajeUsuario ?? error.localizedDescription
            fase = .fallida(mensaje)
            registro.error("Descarga fallida: \(error)", categoria: "descarga")
            if UIApplication.shared.applicationState != .active {
                Notificaciones.enviar(titulo: "La descarga falló", cuerpo: mensaje)
            }
        }
    }

    /// Convierte lo descargado en el archivo final y lo guarda.
    private func procesar(_ resultado: ResultadoDescargaPython, opcion: OpcionCalidad, titulo: String,
                          duracion: Double?, guardarEnFotos: Bool) async throws -> ResultadoFinal {
        let video = resultado.archivos["video"].map { URL(fileURLWithPath: $0) }
        let audio = resultado.archivos["audio"].map { URL(fileURLWithPath: $0) }
        let temporal = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        if opcion.tipo == .audio {
            let salida = temporal.appendingPathExtension("m4a")
            if opcion.extraerAudio, let video {
                try await paso("Extrayendo el audio") { try await Medios.extraerAudio(de: video, destino: salida, progreso: $0) }
            } else if let audio {
                try await paso("Preparando el audio") { _ in try await Medios.normalizarAudio(audio, destino: salida) }
            } else {
                throw ErrorMedios.sinPistaDeAudio
            }
            let final = try Guardado.moverADescargas(salida, titulo: titulo)
            return ResultadoFinal(archivo: final, titulo: titulo, esAudio: true, enFotos: false, avisoFotos: nil)
        }

        let salida = temporal.appendingPathExtension("mp4")
        guard let video else { throw ErrorMedios.sinPistaDeVideo }
        if opcion.unir, let audio {
            try await paso("Uniendo audio y video") {
                try await Medios.unir(video: video, audio: audio, destino: salida, duracionEsperada: duracion, progreso: $0)
            }
        } else {
            try await paso("Preparando el video") {
                try await Medios.prepararVideo(video, destino: salida, duracionEsperada: duracion, progreso: $0)
            }
        }
        let final = try Guardado.moverADescargas(salida, titulo: titulo)

        var enFotos = false
        var aviso: String?
        if guardarEnFotos {
            fase = .procesando("Guardando en Fotos", 1)
            do {
                try await Guardado.guardarEnFotos(final)
                enFotos = true
            } catch {
                aviso = error.localizedDescription
                registro.aviso("No se guardó en Fotos: \(error.localizedDescription)", categoria: "descarga")
            }
        }
        return ResultadoFinal(archivo: final, titulo: titulo, esAudio: false, enFotos: enFotos, avisoFotos: aviso)
    }

    /// Ejecuta un paso de AVFoundation mostrando su nombre y progreso.
    private func paso(_ nombre: String, _ trabajo: (@escaping (Double) -> Void) async throws -> Void) async throws {
        try comprobarCancelacion()
        fase = .procesando(nombre, 0)
        registro.info(nombre, categoria: "descarga")
        try await trabajo { [weak self] valor in
            Task { @MainActor in
                guard let self, case .procesando(let actual, _) = self.fase, actual == nombre else { return }
                self.fase = .procesando(nombre, valor)
            }
        }
        try comprobarCancelacion()
    }

    private func recibir(_ progreso: ProgresoParte) {
        switch fase {
        case .preparando, .descargando:
            acumulador.actualizar(progreso)
            fase = .descargando(acumulador.resumen)
        default:
            break  // llegó tarde: ya se está procesando o se canceló
        }
    }

    private func comprobarCancelacion() throws {
        if cancelacion.activa { throw CancellationError() }
    }

    // MARK: - Utilidades

    /// Partes que hay que pedirle a yt-dlp para una calidad.
    static func partes(de opcion: OpcionCalidad) -> [ParteDescarga] {
        var partes: [ParteDescarga] = []
        if let video = opcion.video { partes.append(ParteDescarga(parte: "video", formato: video)) }
        if let audio = opcion.audio { partes.append(ParteDescarga(parte: "audio", formato: audio)) }
        return partes
    }

    /// Carpeta estable por enlace y calidad: si la descarga se corta, al repetirla yt-dlp
    /// continúa los `.part` en vez de empezar de cero.
    static func nombreCarpeta(url: URL, calidad: String) -> String {
        let huella = SHA256.hash(data: Data(url.absoluteString.utf8))
            .prefix(8).map { String(format: "%02x", $0) }.joined()
        return "\(huella)-\(calidad)"
    }
}

/// Bandera de cancelación que se lee desde el hilo de Python.
final class BanderaCancelacion {
    private let candado = NSLock()
    private var valor = false

    var activa: Bool {
        candado.lock(); defer { candado.unlock() }
        return valor
    }

    func activar() {
        candado.lock(); valor = true; candado.unlock()
    }

    func reiniciar() {
        candado.lock(); valor = false; candado.unlock()
    }
}
