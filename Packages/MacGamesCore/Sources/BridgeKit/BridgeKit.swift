import CryptoKit
import Foundation

public enum BridgeDecision: Equatable, Sendable {
    /// Replace this process with `path`, after removing `unset` from the environment.
    case exec(path: String, argv: [String], unset: [String])
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

    public static func decide(arguments: [String], environment: [String: String], cwd: String,
                              hash: (String) throws -> String) -> BridgeDecision {
        let sidecar = ((arguments.first ?? "") as NSString).deletingLastPathComponent + "/x87sidecar"
        guard arguments.count > 1, arguments[1] == "--cooperative" else {
            return .exec(path: sidecar, argv: [sidecar] + arguments.dropFirst(), unset: [])
        }
        guard arguments.count >= 4, let prefix = environment["WINEPREFIX"] else {
            return .fail("Missing launch context.")
        }
        let loader = arguments[2]
        let game = unixPath(for: arguments[3], prefix: prefix, cwd: cwd)
        if let pin = environment[pinKey], let actual = try? hash(game), actual == pin {
            return .exec(path: sidecar, argv: [sidecar] + arguments.dropFirst(), unset: [])
        }
        var unset = environment.keys.filter { key in optimizationPrefixes.contains(where: key.hasPrefix) }
        if !unset.contains("WINELOADERNOEXEC") { unset.append("WINELOADERNOEXEC") }
        return .exec(path: loader, argv: [loader] + arguments.dropFirst(3), unset: unset.sorted())
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
