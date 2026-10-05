import Foundation

/// Every on-disk location for one game inside the shared Steam library root.
///
/// All games share one engine, one Wine prefix and one Steam client. Only
/// settings and caches are per game, under `games/<id>`. Wine's rpaths
/// (`@loader_path/../../deps/Frameworks`) require `engine/` and `deps/` to sit
/// side by side directly inside the root.
public struct GamePaths: Sendable {
    public let profile: GameProfile
    public let root: URL

    public init(profile: GameProfile, root: URL) {
        self.profile = profile
        self.root = root.standardizedFileURL
    }

    public static func defaultRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/macgames/steam")
    }

    /// Downloads shared by every game (template, Steam installer).
    public static func sharedDownloads(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/macgames/downloads")
    }

    public var frameworks: URL { root.appendingPathComponent("deps/Frameworks") }
    public var engine: URL { root.appendingPathComponent("engine") }
    public var wine: URL { engine.appendingPathComponent("bin/wine") }
    public var wineserver: URL { engine.appendingPathComponent("bin/wineserver") }
    public var prefix: URL { root.appendingPathComponent("prefix") }
    public var logs: URL { root.appendingPathComponent("logs") }
    /// This game's own settings and caches.
    public var gameData: URL { root.appendingPathComponent("games/\(profile.id)") }
    public var graphics: URL { gameData.appendingPathComponent("graphics") }
    public var runtimeReady: URL { root.appendingPathComponent("runtime-ready") }
    public var steamSession: URL { root.appendingPathComponent("steam-session.json") }
    public var steamDir: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam") }
    public var steamExe: URL { steamDir.appendingPathComponent("steam.exe") }
    public var steamapps: URL { steamDir.appendingPathComponent("steamapps") }
    public var appManifest: URL { steamapps.appendingPathComponent("appmanifest_\(profile.steamAppID).acf") }
    public var gameExe: URL {
        steamapps.appendingPathComponent("common/\(profile.installFolder)/\(profile.executableRelativePath)")
    }
}
