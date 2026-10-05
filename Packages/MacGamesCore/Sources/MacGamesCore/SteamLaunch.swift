import Foundation

public enum SteamLaunch {
    public enum Mode: Sendable, Equatable {
        case open
        /// Starts Steam without its window, for helpers that must join its session first.
        case background
        case install
        case play([String])
    }

    public static func arguments(_ paths: GamePaths, _ mode: Mode) -> [String] {
        let profile = paths.profile
        let steam = profile.windowsSteamPath ? paths.windowsPath(paths.steamExe) : paths.steamExe.path
        let base = [steam, "-cef-disable-gpu"] + profile.steamArgs
        switch mode {
        case .open: return base
        case .background: return base + ["-silent"]
        case .install: return base + ["steam://install/\(profile.steamAppID)"]
        case .play(let extra): return base + ["-applaunch", profile.steamAppID] + profile.gameArgs + extra
        }
    }

    /// First-launch CS2 window: borderless, sized to the main display in points.
    public static func cs2DisplayArguments(width: Int, height: Int) -> [String] {
        ["-windowed", "-noborder", "-w", String(width), "-h", String(height)]
    }

    /// Steam hands its environment to the game, so only a game launch, or the background
    /// start just before one, needs a Steam that runs with the current settings. Opening
    /// Steam never interrupts a running session, for example a download.
    public static func needsRestart(_ mode: Mode, sessionRunning: Bool, fingerprintMatches: Bool) -> Bool {
        switch mode {
        case .play, .background: sessionRunning && !fingerprintMatches
        case .open, .install: false
        }
    }

    /// Identifies the managed part of an environment. Steam hands its
    /// environment to the game, so a running Steam with a different
    /// fingerprint must restart before a launch.
    /// Keys a game recipe can change besides the stripped prefixes; they decide where the game
    /// keeps its files and which app it thinks it is.
    static let recipeKeys = ["HOME", "XDG_", "TMPDIR", "SteamAppId", "SteamGameId", "SteamOverlayGameId",
                             "CFFIXED_USER_HOME", "GTM_", "USER", "LOGNAME", "FFXPROXY_", "QT_", "DOTNET_"]

    public static func fingerprint(_ environment: [String: String]) -> String {
        let managed = environment.filter { key, _ in
            (WineEnvironment.strippedPrefixes + recipeKeys).contains { key == $0 || key.hasPrefix($0) }
        }
        let text = managed.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "\n")
        return sha256Hex(Data(text.utf8))
    }
}

/// What MacGames knows about the Steam session it started last.
public struct SteamSession: Codable, Sendable, Equatable {
    public let fingerprint: String
    /// Size of Steam's game process log when the session began.
    public let gameLogOffset: UInt64
    /// Sync settings the session's wineserver runs with; a joining process must match them.
    public var serverKeys: [String: String]?

    static let serverKeyNames = ["WINEMSYNC", "WINEESYNC", "WINEFSYNC"]

    public init(fingerprint: String, gameLogOffset: UInt64, serverKeys: [String: String]? = nil) {
        self.fingerprint = fingerprint
        self.gameLogOffset = gameLogOffset
        self.serverKeys = serverKeys
    }

    /// `environment` adjusted to the running server's sync settings.
    public func join(_ environment: [String: String]) -> [String: String] {
        var env = environment
        for (key, value) in serverKeys ?? [:] { env[key] = value }
        return env
    }

    public static func load(_ paths: GamePaths) -> SteamSession? {
        try? JSONDecoder().decode(SteamSession.self, from: Data(contentsOf: paths.steamSession))
    }

    public static func begin(fingerprint: String, paths: GamePaths, environment: [String: String] = [:]) throws {
        let size = (try? FileManager.default.attributesOfItem(atPath: GameProcessLog.url(paths).path)[.size] as? UInt64) ?? 0
        let keys = environment.filter { serverKeyNames.contains($0.key) }
        let session = SteamSession(fingerprint: fingerprint, gameLogOffset: size, serverKeys: keys.isEmpty ? nil : keys)
        try JSONEncoder().encode(session).write(to: paths.steamSession, options: .atomic)
    }
}
