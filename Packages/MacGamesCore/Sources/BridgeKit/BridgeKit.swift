import CryptoKit
import Foundation

public enum BridgeDecision: Equatable, Sendable {
    /// Replace this process with `path`, after removing `unset` from the environment and adding `set`.
    case exec(path: String, argv: [String], unset: [String], set: [String: String])
    case fail(String)
}

/// Decides how the patched Wine loader's re-exec of the game continues.
///
/// Wine calls `AOELAB_SIDECAR_PATH --cooperative <loader> <game.exe> <args...>`.
/// The x87sidecar optimization patches fixed addresses, so it may only run on
/// the exact build it was made for; any other build runs on the plain loader.
public enum Bridge {
    static let optimizationPrefixes = ["AOELAB_", "AOE_SOFTFAULT_", "X87_", "MACGAMES_"]
    public static let pinKey = "MACGAMES_OPTIMIZED_SHA256"
    /// The pinned build's software-fault range end. It replaces the end Wine sets for the old build.
    public static let softfaultEndKey = "MACGAMES_SOFTFAULT_END"
    /// x87sidecar installs no decode hook for a longer range.
    static let maximumSoftfaultRange: UInt64 = 0x6000000

    public static func decide(arguments: [String], environment: [String: String], cwd: String,
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                              hash: (String) throws -> String) -> BridgeDecision {
        let sidecar = ((arguments.first ?? "") as NSString).deletingLastPathComponent + "/x87sidecar"
        guard arguments.count > 1, arguments[1] == "--cooperative" else {
            return .exec(path: sidecar, argv: [sidecar] + arguments.dropFirst(), unset: [], set: [:])
        }
        guard arguments.count >= 4, let prefix = environment["WINEPREFIX"] else {
            return .fail("Missing launch context.")
        }
        let loader = arguments[2]
        let game = unixPath(for: arguments[3], prefix: prefix, cwd: cwd)
        // The game still starts on the plain loader if the sidecar is missing.
        if isExecutable(sidecar), let pin = environment[pinKey], let actual = try? hash(game), actual == pin,
           let set = softfaultRange(environment) {
            // Runtime 4 disables x87 for its old softfault-only decoder.
            // The rebuilt decoder composes both paths; keep the EXE guard above.
            let unset = environment["MACGAMES_AOE_COMBINED"] == "1" ? ["X87_ALWAYS_NONE"] : []
            return .exec(path: sidecar, argv: [sidecar] + arguments.dropFirst(), unset: unset, set: set)
        }
        var unset = environment.keys.filter { key in optimizationPrefixes.contains(where: key.hasPrefix) }
        if !unset.contains("WINELOADERNOEXEC") { unset.append("WINELOADERNOEXEC") }
        return .exec(path: loader, argv: [loader] + arguments.dropFirst(3), unset: unset.sorted(), set: [:])
    }

    /// The range end to give the sidecar: none keeps Wine's own, and `nil` means it is unusable.
    static func softfaultRange(_ environment: [String: String]) -> [String: String]? {
        guard let value = environment[softfaultEndKey] else { return [:] }
        guard let end = hex(value), let start = environment["AOE_SOFTFAULT_PC"].flatMap(hex),
              end > start, end - start <= maximumSoftfaultRange else { return nil }
        return ["AOE_SOFTFAULT_END": value]
    }

    /// `0x` followed by hex digits only, as Wine writes its addresses.
    static func hex(_ text: String) -> UInt64? {
        guard text.hasPrefix("0x") else { return nil }
        let digits = text.dropFirst(2)
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }
        return UInt64(digits, radix: 16)
    }

    public static func unixPath(for argument: String, prefix: String, cwd: String) -> String {
        let path = argument.replacingOccurrences(of: "\\", with: "/")
        if path.lowercased().hasPrefix("c:/") {
            return (prefix as NSString).appendingPathComponent("drive_c/" + path.dropFirst(3))
        }
        if path.hasPrefix("/") { return path }
        return (cwd as NSString).appendingPathComponent(path)
    }

    public static func sha256(ofFileAt path: String) throws -> String {
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
