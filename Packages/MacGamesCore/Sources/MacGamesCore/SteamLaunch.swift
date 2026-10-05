import Foundation

public enum SteamLaunch {
    public enum Mode: Sendable, Equatable {
        case open
        case install
        case play([String])
    }

    public static func arguments(_ paths: GamePaths, _ mode: Mode) -> [String] {
        let base = [paths.steamExe.path, "-cef-disable-gpu"]
        switch mode {
        case .open: return base
        case .install: return base + ["steam://install/\(paths.profile.steamAppID)"]
        case .play(let extra): return base + ["-applaunch", paths.profile.steamAppID] + extra
        }
    }

    /// First-launch CS2 window: borderless, sized to the main display in points.
    public static func cs2DisplayArguments(width: Int, height: Int) -> [String] {
        ["-windowed", "-noborder", "-w", String(width), "-h", String(height)]
    }

    /// Identifies the managed part of an environment. Steam hands its
    /// environment to the game, so a running Steam with a different
    /// fingerprint must restart before a launch.
    public static func fingerprint(_ environment: [String: String]) -> String {
        let managed = environment.filter { key, _ in WineEnvironment.strippedPrefixes.contains(where: key.hasPrefix) }
        let text = managed.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        return sha256Hex(Data(text.utf8))
    }
}
