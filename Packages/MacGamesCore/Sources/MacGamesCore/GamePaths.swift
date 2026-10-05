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

    /// The root of the shared `steam` environment.
    public static func defaultRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        defaultRoot(for: .steam, home: home)
    }

    public static func defaultRoot(for environment: GameEnvironment,
                                   home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/Application Support/macgames/\(environment.id)")
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
    public var environment: GameEnvironment { profile.gameEnvironment }
    /// Downloaded packs of this environment, one folder each.
    public var packs: URL { root.appendingPathComponent("packs") }
    public func pack(_ name: String) -> URL { packs.appendingPathComponent(name) }

    /// Where D3DMetal's Wine side lives: the template, or a pack for environments that pin another build.
    public var d3dmetal: URL {
        environment.d3dmetalPack.map { pack($0) } ?? frameworks.appendingPathComponent("renderer/d3dmetal")
    }

    public var battleNetExe: URL { prefix.appendingPathComponent("drive_c/Program Files (x86)/Battle.net/Battle.net.exe") }

    /// The game's install folder: under Steam's library, or under Program Files for Battle.net.
    public var installDir: URL {
        profile.launch == .battleNet
            ? prefix.appendingPathComponent("drive_c/Program Files (x86)/\(profile.installFolder)")
            : steamapps.appendingPathComponent("common/\(profile.installFolder)")
    }

    public var gameExe: URL { installDir.appendingPathComponent(profile.executableRelativePath) }

    /// The `C:` path of a file inside `drive_c`.
    public func windowsPath(_ url: URL) -> String {
        let drive = prefix.appendingPathComponent("drive_c").standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(drive) else { return path }
        return "C:" + path.dropFirst(drive.count).replacingOccurrences(of: "/", with: "\\")
    }
}
