import Foundation

/// Datos de la compilación y del dispositivo.
///
/// Se muestran en Ajustes y encabezan el Registro: así, cuando me pegues un log,
/// sé exactamente qué build tienes instalado y en qué iPhone.
enum InfoBuild {
    /// Lee una clave de texto del Info.plist de la app.
    private static func valor(_ clave: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: clave) as? String) ?? "?"
    }

    /// Versión visible, p. ej. "0.1.0".
    static var version: String { valor("CFBundleShortVersionString") }

    /// Número de build; en GitHub Actions es el número de ejecución del workflow.
    static var build: String { valor("CFBundleVersion") }

    /// Commit corto con el que se compiló ("local" si no viene de CI).
    static var commit: String { valor("DescargadorCommit") }

    /// Versión de iOS, p. ej. "iOS 17.6.1". Usa ProcessInfo para no depender del hilo principal.
    static var sistema: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let parche = v.patchVersion > 0 ? ".\(v.patchVersion)" : ""
        return "iOS \(v.majorVersion).\(v.minorVersion)\(parche)"
    }

    /// Identificador del modelo, p. ej. "iPhone14,2". En el simulador devuelve el modelo simulado.
    static var modelo: String {
        if let simulado = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return "\(simulado) (simulador)"
        }
        var info = utsname()
        uname(&info)
        let maquina = withUnsafeBytes(of: info.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return maquina.isEmpty ? "desconocido" : maquina
    }

    /// Línea completa, p. ej. "Descargador 0.1.0 (build 12, commit abc1234) · iOS 17.6.1 · iPhone14,2".
    static var resumen: String {
        "Descargador \(version) (build \(build), commit \(commit)) · \(sistema) · \(modelo)"
    }
}
