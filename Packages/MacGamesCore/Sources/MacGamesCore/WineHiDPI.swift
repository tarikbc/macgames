import Foundation

enum WineHiDPI {
    static let key = #"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#

    static func isRetinaMode(_ value: RegistryValue) -> Bool {
        value.key.caseInsensitiveCompare(key) == .orderedSame &&
            value.name.caseInsensitiveCompare("RetinaMode") == .orderedSame
    }

    static func registryValue(_ enabled: Bool) -> RegistryValue {
        RegistryValue(key: key, name: "RetinaMode", value: .string(enabled ? "Y" : "N"))
    }

    /// Read an older installation's preference without starting a Wine process.
    static func currentValue(in prefix: URL) -> Bool? {
        guard let contents = try? String(contentsOf: prefix.appendingPathComponent("user.reg"), encoding: .utf8) else { return nil }
        var inSection = false
        for rawLine in contents.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inSection = line.lowercased().hasPrefix(#"[software\\wine\\mac driver]"#)
            } else if inSection, line.lowercased().hasPrefix(#""retinamode"=""#) {
                let value = line.dropFirst(#""RetinaMode"="#.count).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                guard let first = value.lowercased().first else { return false }
                return "yt1".contains(first)
            }
        }
        return nil
    }
}
