import Foundation

public enum SteamLaunch {
    public enum Mode: Sendable, Equatable {
        case open
        case install
        case play([String])
    }

    public static func arguments(_ paths: GamePaths, _ mode: Mode) -> [String] {
        let profile = paths.profile
        let steam = profile.windowsSteamPath ? paths.windowsPath(paths.steamExe) : paths.steamExe.path
        let base = [steam, "-cef-disable-gpu"] + profile.steamArgs
        switch mode {
        case .open: return base
        case .install: return base + ["steam://install/\(profile.steamAppID)"]
        case .play(let extra): return base + ["-applaunch", profile.steamAppID] + profile.gameArgs + extra
        }
    }

    /// First-launch CS2 window: borderless, sized to the main display in points.
    public static func cs2DisplayArguments(width: Int, height: Int) -> [String] {
        ["-windowed", "-noborder", "-w", String(width), "-h", String(height)]
    }

    /// Steam hands its environment to the game, so only a game launch needs a
    /// Steam that runs with the current settings. Opening Steam never
    /// interrupts a running session, for example a download.
    public static func needsRestart(_ mode: Mode, sessionRunning: Bool, fingerprintMatches: Bool) -> Bool {
        guard case .play = mode else { return false }
        return sessionRunning && !fingerprintMatches
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

/// What MacGames knows about the Steam session it started last.
public struct SteamSession: Codable, Sendable, Equatable {
    public let fingerprint: String
    /// Size of Steam's game process log when the session began.
    public let gameLogOffset: UInt64

    public static func load(_ paths: GamePaths) -> SteamSession? {
        try? JSONDecoder().decode(SteamSession.self, from: Data(contentsOf: paths.steamSession))
    }

    public static func begin(fingerprint: String, paths: GamePaths) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: GameProcessLog.url(paths).path)[.size] as? UInt64) ?? 0
        let session = SteamSession(fingerprint: fingerprint, gameLogOffset: size)
        try JSONEncoder().encode(session).write(to: paths.steamSession, options: .atomic)
    }
}
