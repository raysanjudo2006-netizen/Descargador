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

        // 2. La calidad puede ir antes de "url=" o al final (se parte en la ÚLTIMA aparición).
        var calidad = calidadEn(parametros: previo)
        if let r = valor.range(of: "&calidad=", options: .backwards) {
            calidad = calidadEn(parametros: valor[r.lowerBound...].dropFirst())
            valor = String(valor[..<r.lowerBound])
        }

        // 3. Si ya empieza por http(s):// viene sin codificar y se usa tal cual
        //    (decodificarla estropearía porcentajes propios como "%20").
        let minusculas = valor.lowercased()
        let texto: String
        if minusculas.hasPrefix("http://") || minusculas.hasPrefix("https://") {
            texto = valor
        } else if let decodificado = valor.removingPercentEncoding {
            texto = decodificado
        } else {
            return nil
        }

        guard let url = URL(string: texto), esWeb(url) else { return nil }
        return PeticionDescarga(url: url, calidad: calidad)
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
