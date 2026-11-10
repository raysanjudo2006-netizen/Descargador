import Foundation

/// Lo que llega por el esquema `descargador://download?url=…[&calidad=…]`
/// (Share Extension, Atajos o Safari).
struct PeticionDescarga: Equatable {
    let url: URL
    let calidad: Calidad?
}

/// Utilidades para encontrar enlaces en texto y leer el esquema de la app.
enum Enlaces {
    static let esquema = "descargador"

    /// Devuelve el primer enlace http(s) que aparezca en el texto.
    ///
    /// Sirve para lo que se pega o se comparte: TikTok, por ejemplo, comparte
    /// "Mira este video… https://vm.tiktok.com/… #fyp". También acepta enlaces
    /// sin esquema como "youtu.be/abc".
    static func extraerPrimerEnlace(de texto: String) -> URL? {
        let limpio = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !limpio.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return nil }
        let rango = NSRange(limpio.startIndex..., in: limpio)
        for coincidencia in detector.matches(in: limpio, options: [], range: rango) {
            if let url = coincidencia.url, esWeb(url) {
                return url
            }
        }
        return nil
    }

    /// `true` si el enlace es http/https y tiene host.
    static func esWeb(_ url: URL) -> Bool {
        guard let esquema = url.scheme?.lowercased(), esquema == "http" || esquema == "https" else {
            return false
        }
        return !(url.host ?? "").isEmpty
    }

    /// Interpreta `descargador://download?url=…&calidad=…`.
    ///
    /// Acepta la URL interna codificada (lo correcto, con "Codificar URL" en Atajos) y también
    /// sin codificar, aunque traiga sus propios `&` (p. ej. `watch?v=abc&t=10`): por eso no se usa
    /// `queryItems`, que la partiría en trozos.
    static func peticion(desde enlace: URL) -> PeticionDescarga? {
        guard enlace.scheme?.lowercased() == esquema,
              enlace.host?.lowercased() == "download",
              let consulta = URLComponents(url: enlace, resolvingAgainstBaseURL: false)?.percentEncodedQuery
        else { return nil }

        // 1. Localiza "url=" al principio de la consulta o tras un "&".
        let inicioValor: String.Index
        let previo: Substring
        if consulta.hasPrefix("url=") {
            inicioValor = consulta.index(consulta.startIndex, offsetBy: 4)
            previo = ""
        } else if let r = consulta.range(of: "&url=") {
            inicioValor = r.upperBound
            previo = consulta[..<r.lowerBound]
        } else {
            return nil
        }
        var valor = String(consulta[inicioValor...])
        var calidad = calidadEn(parametros: previo)

        let minusculas = valor.lowercased()
        let texto: String
        if minusculas.hasPrefix("http://") || minusculas.hasPrefix("https://") {
            // 2a. Sin codificar: puede traer sus propios "&", así que solo se separa la calidad
            //     en su ÚLTIMA aparición. Se usa tal cual (decodificarla estropearía "%20" propios)
            //     y se le devuelve el fragmento "#…", que URL asigna al enlace exterior.
            if let r = valor.range(of: "&calidad=", options: .backwards) {
                calidad = calidadEn(parametros: valor[r.lowerBound...].dropFirst()) ?? calidad
                valor = String(valor[..<r.lowerBound])
            }
            if let fragmento = enlace.fragment, !fragmento.isEmpty {
                valor += "#" + fragmento
            }
            texto = valor
        } else {
            // 2b. Codificada: no contiene "&" propios, así que termina en el primer "&";
            //     el resto son otros parámetros (calidad u otros que se ignoran).
            let partes = valor.split(separator: "&", maxSplits: 1, omittingEmptySubsequences: false)
            if partes.count == 2 {
                calidad = calidadEn(parametros: partes[1]) ?? calidad
            }
            guard let primera = partes.first, let decodificado = String(primera).removingPercentEncoding else {
                return nil
            }
            texto = decodificado
        }

        // Lo normal es una URL limpia; pero si un atajo pasó el texto compartido entero
        // ("Mira esto… https://vm.tiktok.com/… #fyp"), se busca el enlace dentro.
        if let url = URL(string: texto), esWeb(url) {
            return PeticionDescarga(url: url, calidad: calidad)
        }
        guard let url = extraerPrimerEnlace(de: texto) else { return nil }
        return PeticionDescarga(url: url, calidad: calidad)
    }

    /// Construye `descargador://download?url=…[&calidad=…]` con la URL interna codificada
    /// por completo (así sus propios `&` y `#` llegan intactos). Lo usan la Share Extension y Atajos.
    static func enlaceProfundo(para url: URL, calidad: Calidad? = nil) -> URL {
        let permitidos = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        let codificada = url.absoluteString.addingPercentEncoding(withAllowedCharacters: permitidos) ?? ""
        var texto = "\(esquema)://download?url=\(codificada)"
        if let calidad {
            texto += "&calidad=\(calidad.rawValue)"
        }
        // Solo contiene caracteres ASCII seguros, así que siempre es una URL válida.
        return URL(string: texto) ?? URL(fileURLWithPath: "/")
    }

    /// Busca `calidad=…` en una lista de parámetros "a=1&b=2".
    private static func calidadEn(parametros: Substring) -> Calidad? {
        for parametro in parametros.split(separator: "&") {
            let partes = parametro.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if partes.count == 2, partes[0].lowercased() == "calidad" {
                return Calidad(rawValue: partes[1].lowercased())
            }
        }
        return nil
    }
}
