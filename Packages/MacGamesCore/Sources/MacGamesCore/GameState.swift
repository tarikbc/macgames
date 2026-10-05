import Foundation

public enum GameState: String, Sendable, Equatable {
    case notSetUp
    case needsSteam
    case needsGame
    case installing
    case ready
    case running

    /// Reads the setup stage from disk. `sessionRunning` says whether this
    /// game's Wine session is alive; Steam's log alone can be stale.
    public static func derive(_ paths: GamePaths, sessionRunning: Bool) -> GameState {
        let fm = FileManager.default
        guard fm.fileExists(atPath: paths.runtimeReady.path) else { return .notSetUp }
        guard fm.fileExists(atPath: paths.steamExe.path) else { return .needsSteam }
        guard let manifest = AppManifest(contentsOf: paths.appManifest) else { return .needsGame }
        guard manifest.isFullyInstalled(paths.profile), fm.fileExists(atPath: paths.gameExe.path) else { return .installing }
        if sessionRunning && GameProcessLog.isRunning(paths.profile, paths: paths) { return .running }
        return .ready
    }
}

public struct LaunchSettings: Codable, Sendable, Equatable {
    /// Use the x87sidecar optimization when the profile and this Mac support it.
    public var optimized: Bool
    /// Show the Metal performance HUD.
    public var hud: Bool

    public init(optimized: Bool = true, hud: Bool = false) {
        self.optimized = optimized
        self.hud = hud
    }

    static func url(_ paths: GamePaths) -> URL { paths.root.appendingPathComponent("settings.json") }

    public static func load(from paths: GamePaths) -> LaunchSettings {
        (try? JSONDecoder().decode(LaunchSettings.self, from: Data(contentsOf: url(paths)))) ?? LaunchSettings()
    }

    public func save(to paths: GamePaths) throws {
        try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: Self.url(paths), options: .atomic)
    }
}
