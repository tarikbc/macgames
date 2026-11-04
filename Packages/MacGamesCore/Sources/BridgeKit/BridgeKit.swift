import Foundation

public enum BridgeDecision: Equatable, Sendable {
    /// Replace this process with `path`, after removing `unset` from the environment and adding `set`.
    case exec(path: String, argv: [String], unset: [String], set: [String: String])
    case fail(String)
}

/// Decides how the patched Wine loader's re-exec of the game continues.
///
/// Wine calls `AOELAB_SIDECAR_PATH --cooperative <loader> <game.exe> <args...>`.
/// The x87sidecar software-fault hook covers a fixed address range. The bridge reads
/// that range from the game's own headers, so any build whose layout fits runs the
/// sidecar; anything it cannot verify runs on the plain loader.
public enum Bridge {
    static let optimizationPrefixes = ["AOELAB_", "AOE_SOFTFAULT_", "X87_", "MACGAMES_"]
    /// MacGames sets this to "1" when the user turned the optimization on.
    public static let optedInKey = "MACGAMES_OPTIMIZED"

    public static func decide(arguments: [String], environment: [String: String], cwd: String,
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
                              image: (String) throws -> GameImage?) -> BridgeDecision {
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
        if isExecutable(sidecar), environment[optedInKey] == "1",
           let start = environment["AOE_SOFTFAULT_PC"].flatMap(hex),
           let found = try? image(game), let end = found.softfaultEnd(start: start) {
            // Runtime 4 disables x87 for its old softfault-only decoder.
            // The rebuilt decoder composes both paths; keep the header check above.
            let unset = environment["MACGAMES_AOE_COMBINED"] == "1" ? ["X87_ALWAYS_NONE"] : []
            // Wine's own end belongs to the old build, so it is always replaced.
            return .exec(path: sidecar, argv: [sidecar] + arguments.dropFirst(), unset: unset,
                         set: ["AOE_SOFTFAULT_END": "0x" + String(end, radix: 16)])
        }
        var unset = environment.keys.filter { key in optimizationPrefixes.contains(where: key.hasPrefix) }
        if !unset.contains("WINELOADERNOEXEC") { unset.append("WINELOADERNOEXEC") }
        return .exec(path: loader, argv: [loader] + arguments.dropFirst(3), unset: unset.sorted(), set: [:])
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
}
