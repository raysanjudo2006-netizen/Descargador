import AVFoundation
import UIKit
import UserNotifications

/// Mantener la descarga viva cuando la app pasa a segundo plano (opción B del diseño).
///
/// - Siempre: `beginBackgroundTask` (iOS da unos 30 s). Si se acaba, se avisa con una
///   notificación local; al volver a la app, yt-dlp reintenta y continúa el `.part`.
/// - Si "Mantener activo" está activado: además se reproduce silencio en bucle (sesión de
///   audio `.playback` + `.mixWithOthers`, no corta tu música), y iOS no suspende la app.
@MainActor
final class SegundoPlano {
    private let registro: Registro
    private var tareaFondo: UIBackgroundTaskIdentifier = .invalid
    private var reproductor: AVAudioPlayer?
    private var observadorInterrupciones: NSObjectProtocol?
    private var tituloActual = ""

    init(registro: Registro = .compartido) {
        self.registro = registro
    }

    func comenzar(titulo: String, mantenerActivo: Bool) {
        tituloActual = titulo
        if tareaFondo == .invalid {
            tareaFondo = UIApplication.shared.beginBackgroundTask(withName: "Descarga") { [weak self] in
                Task { @MainActor in self?.tiempoAgotado() }
            }
        }
        if mantenerActivo {
            iniciarSilencio()
        }
    }

    func terminar() {
        detenerSilencio()
        if tareaFondo != .invalid {
            UIApplication.shared.endBackgroundTask(tareaFondo)
            tareaFondo = .invalid
        }
    }

    private func tiempoAgotado() {
        if reproductor == nil {
            registro.aviso("iOS suspende la app: la descarga se pausa hasta que vuelvas", categoria: "descarga")
            Notificaciones.enviar(titulo: "Descarga en pausa",
                                  cuerpo: "Abre Descargador para continuar «\(tituloActual)». Para que no se pause, activa «Mantener activo» en Ajustes.")
        }
        if tareaFondo != .invalid {
            UIApplication.shared.endBackgroundTask(tareaFondo)
            tareaFondo = .invalid
        }
    }

    // MARK: - Audio silencioso

    private func iniciarSilencio() {
        guard reproductor == nil else { return }
        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try sesion.setActive(true)
            let jugador = try AVAudioPlayer(data: Self.silencioWAV)
            jugador.numberOfLoops = -1
            jugador.volume = 0
            jugador.play()
            reproductor = jugador
            // Una llamada interrumpe el audio: al terminar, se reanuda.
            observadorInterrupciones = NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
            ) { [weak self] aviso in
                let tipo = (aviso.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                    .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
                if tipo == .ended {
                    Task { @MainActor in self?.reproductor?.play() }
                }
            }
            registro.info("Mantener activo: audio silencioso en marcha", categoria: "descarga")
        } catch {
            registro.aviso("No se pudo activar «Mantener activo»: \(error.localizedDescription)", categoria: "descarga")
        }
    }

    private func detenerSilencio() {
        guard let jugador = reproductor else { return }
        jugador.stop()
        reproductor = nil
        if let observadorInterrupciones {
            NotificationCenter.default.removeObserver(observadorInterrupciones)
        }
        observadorInterrupciones = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 1 segundo de silencio en WAV (PCM 16 bits, 8 kHz, mono), generado en memoria.
    private static let silencioWAV: Data = {
        let frecuencia: UInt32 = 8_000
        let bytesAudio = frecuencia * 2
        var datos = Data()
        func agregar<T: FixedWidthInteger>(_ valor: T) {
            withUnsafeBytes(of: valor.littleEndian) { datos.append(contentsOf: $0) }
        }
        datos.append(contentsOf: Array("RIFF".utf8)); agregar(UInt32(36 + bytesAudio))
        datos.append(contentsOf: Array("WAVE".utf8))
        datos.append(contentsOf: Array("fmt ".utf8)); agregar(UInt32(16))
        agregar(UInt16(1)); agregar(UInt16(1))                  // PCM, mono
        agregar(frecuencia); agregar(frecuencia * 2)            // frecuencia, bytes por segundo
        agregar(UInt16(2)); agregar(UInt16(16))                 // bytes por muestra, bits
        datos.append(contentsOf: Array("data".utf8)); agregar(bytesAudio)
        datos.append(Data(count: Int(bytesAudio)))
        return datos
    }()
}

/// Notificaciones locales (no requieren cuenta de pago, a diferencia de las push).
enum Notificaciones {
    static func pedirPermiso() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    /// Envía un aviso inmediato; iOS solo lo muestra si la app no está en primer plano.
    static func enviar(titulo: String, cuerpo: String) {
        let contenido = UNMutableNotificationContent()
        contenido.title = titulo
        contenido.body = cuerpo
        contenido.sound = .default
        let peticion = UNNotificationRequest(identifier: UUID().uuidString, content: contenido, trigger: nil)
        UNUserNotificationCenter.current().add(peticion)
    }
}
