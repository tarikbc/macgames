import Foundation

public struct RegistryValue: Sendable, Equatable {
    public enum Value: Sendable, Equatable {
        case string(String)
        case dword(UInt32)

        var text: String {
            switch self {
            case .string(let s): s
            case .dword(let d): String(d)
            }
        }
    }

    /// Full key path with the hive spelled out, for example `HKEY_CURRENT_USER\Software\…`.
    public let key: String
    public let name: String
    public let value: Value

    public init(key: String, name: String, value: Value) {
        self.key = key; self.name = name; self.value = value
    }

    static let appDefaults = #"HKEY_CURRENT_USER\Software\Wine\AppDefaults\"#

    /// A per-executable DLL load order, which keeps one game's renderer choice away from the others.
    static func dll(_ exe: String, _ name: String, _ order: String) -> RegistryValue {
        RegistryValue(key: appDefaults + exe + #"\DllOverrides"#, name: name, value: .string(order))
    }

    /// The Windows version Wine reports to one executable.
    static func windowsVersion(_ exe: String, _ version: String) -> RegistryValue {
        RegistryValue(key: appDefaults + exe, name: "Version", value: .string(version))
    }
}

/// Writes registry values as a `.reg` file for `wine reg import`: one Wine
/// start for all values instead of one per `reg add`.
///
/// Wine reads a REGEDIT4 file in the ANSI code page, which breaks paths with
/// non-ASCII names, so the file uses the version 5 format in UTF-16LE.
public enum RegistryFile {
    /// The file contents: a UTF-16LE byte order mark, then `render`.
    public static func data(_ values: [RegistryValue]) -> Data {
        Data([0xFF, 0xFE]) + render(values).data(using: .utf16LittleEndian)!
    }

    public static func render(_ values: [RegistryValue]) -> String {
        var out = "Windows Registry Editor Version 5.00\n"
        var lastKey: String?
        for v in values {
            if v.key != lastKey { out += "\n[\(v.key)]\n"; lastKey = v.key }
            let name = escape(v.name)
            switch v.value {
            case .string(let s): out += "\"\(name)\"=\"\(escape(s))\"\n"
            case .dword(let d): out += "\"\(name)\"=dword:\(String(format: "%08x", d))\n"
            }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
