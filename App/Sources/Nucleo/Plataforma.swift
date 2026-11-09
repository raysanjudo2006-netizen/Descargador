import Foundation

/// Plataforma de origen de un enlace. Solo sirve para mostrar nombre e icono:
/// yt-dlp acepta muchas más webs, que aparecen como `.otra`.
enum Plataforma: String, CaseIterable, Codable {
    case youtube, instagram, tiktok, x, facebook, otra

    /// Nombre visible en la interfaz.
    var nombre: String {
        switch self {
        case .youtube: return "YouTube"
        case .instagram: return "Instagram"
        case .tiktok: return "TikTok"
        case .x: return "X"
        case .facebook: return "Facebook"
        case .otra: return "Otra web"
        }
    }

    /// Símbolo SF Symbols (genérico: no usamos logotipos de marca).
    var simbolo: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .instagram: return "camera.fill"
        case .tiktok: return "music.note"
        case .x: return "text.bubble.fill"
        case .facebook: return "person.2.fill"
        case .otra: return "globe"
        }
    }

    /// Dominios raíz de cada plataforma; también cuentan sus subdominios (m., music., vm.…).
    private var dominios: [String] {
        switch self {
        case .youtube: return ["youtube.com", "youtu.be", "youtube-nocookie.com"]
        case .instagram: return ["instagram.com", "instagr.am"]
        case .tiktok: return ["tiktok.com"]
        case .x: return ["x.com", "twitter.com"]
        case .facebook: return ["facebook.com", "fb.watch", "fb.com"]
        case .otra: return []
        }
    }

    /// Detecta la plataforma por el host. "notyoutube.com" o "youtube.com.evil.net" NO son YouTube.
    static func detectar(_ url: URL) -> Plataforma {
        guard let host = url.host?.lowercased(), !host.isEmpty else { return .otra }
        for plataforma in allCases where plataforma != .otra {
            let coincide = plataforma.dominios.contains { dominio in
                host == dominio || host.hasSuffix("." + dominio)
            }
            if coincide { return plataforma }
        }
        return .otra
    }
}
