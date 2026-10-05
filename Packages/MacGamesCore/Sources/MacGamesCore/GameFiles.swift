import Foundation

/// What the display looks like at launch, measured by the app (which has AppKit).
public struct LaunchContext: Sendable, Equatable {
    /// Main display size in points.
    public var width: Int
    public var height: Int
    /// The main display has a camera housing at the top.
    public var hasNotch: Bool

    public init(width: Int, height: Int, hasNotch: Bool = false) {
        self.width = width; self.height = height; self.hasNotch = hasNotch
    }
}

/// File changes some games need inside their install or settings folders.
/// Each one only touches files it recognizes, and keeps the user's own values.
public enum GameFiles {
    static func sha(_ url: URL) -> String? { try? sha256Hex(ofFileAt: url) }

    /// The Windows user folders of a prefix (Wine names the user after the Mac account or "crossover").
    static func userFolders(_ paths: GamePaths) -> [URL] {
        let users = paths.prefix.appendingPathComponent("drive_c/users")
        return ((try? FileManager.default.contentsOfDirectory(at: users, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent != "Public" }
    }

    static func edit(_ url: URL, _ change: (String) -> String) throws {
        let fm = FileManager.default
        let old = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let new = change(old)
        guard new != old else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: url.path + ".macgames-backup") {
            try fm.copyItem(atPath: url.path, toPath: url.path + ".macgames-backup")
        }
        try new.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Replaces `original` in place with `replacement`, keeping the original as `<name>_orig`, but only
    /// when the file is the build MacGames expects (or already replaced).
    static func swapIn(_ replacement: URL, at original: URL, expectedOriginalSHA: String?, keepOriginalAs backupName: String? = nil) throws {
        let fm = FileManager.default
        let wanted = sha(replacement)
        if sha(original) == wanted { return }
        guard fm.fileExists(atPath: original.path) else { throw SetupError("\(original.lastPathComponent) is missing. Verify the game files in Steam.") }
        if let expectedOriginalSHA, sha(original) != expectedOriginalSHA {
            throw SetupError("\(original.lastPathComponent) is a build MacGames does not know, so it was left unchanged.")
        }
        if let backupName {
            let backup = original.deletingLastPathComponent().appendingPathComponent(backupName)
            if fm.fileExists(atPath: backup.path) { try fm.removeItem(at: backup) }
            try fm.copyItem(at: original, to: backup)
        }
        try fm.removeItem(at: original)
        try fm.copyItem(at: replacement, to: original)
    }

    static func copyIfMissing(_ from: URL, to: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: to.path) else { return }
        try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: from, to: to)
    }

    // MARK: Per game

    public static let witcherLoaderSHA = "e2d85aa05a9bd9ed8b38935fdf5199372cca6f74c12015143bb6f945ee1608aa"
    public static let heroesRendererSHA = "2f1399ef5e6cdba02495fbb66c731924c9a7b0b40b43b8b496dfb18993328039"

    /// Steps that only change files, run before each launch.
    public static func prepare(_ profile: GameProfile, paths: GamePaths, runtime: RuntimeLayout, context: LaunchContext,
                               witcherSHA: String? = witcherLoaderSHA, heroesSHA: String? = heroesRendererSHA,
                               heroesAudioSHAs: (String?, String?) = (HeroesAudio.originalSHA, HeroesAudio.fixedSHA)) throws {
        let files = runtime.gameFiles(profile.id)
        let game = paths.installDir
        switch profile.id {
        case "hogwarts-legacy":
            // Without this the game warns about an unsupported AMD driver on every start.
            for user in userFolders(paths) {
                try edit(user.appendingPathComponent("AppData/Local/Hogwarts Legacy/Saved/Config/WindowsNoEditor/Engine.ini")) {
                    INIFile.set(in: $0, section: "SystemSettings", key: "r.WarnOfBadDrivers", value: "0")
                }
            }
        case "poe2":
            for user in userFolders(paths) {
                try edit(user.appendingPathComponent("Documents/My Games/Path of Exile 2/poe2_production_Config.ini")) { text in
                    var t = INIFile.set(in: text, section: "DISPLAY", key: "renderer_type", value: "DirectX12")
                    for (key, value) in [("fullscreen", "false"), ("borderless_windowed_fullscreen", "true"), ("maximize_window", "true")] {
                        t = INIFile.set(in: t, section: "DISPLAY", key: key, value: value, onlyIfMissing: true)
                    }
                    return INIFile.set(in: t, section: "GENERAL", key: "engine_multithreading_mode", value: "enabled", onlyIfMissing: true)
                }
            }
        case "zero-hour":
            for user in userFolders(paths) {
                let options = user.appendingPathComponent("Documents/Command and Conquer Generals Zero Hour Data/Options.ini")
                try edit(options) { text in
                    var t = text.isEmpty
                        ? "Resolution = \(min(max(context.width, 800), 1920)) \(min(max(context.height, 600), 1200))\r\n" : text
                    for key in ["ScreenEdgeScrollEnabledInFullscreenApp", "ScreenEdgeScrollEnabledInWindowedApp",
                                "CursorCaptureEnabledInFullscreenGame", "CursorCaptureEnabledInWindowedGame"] {
                        t = INIFile.set(in: t, section: nil, key: key, value: "yes", separator: " = ")
                    }
                    return t
                }
            }
        case "red-alert2":
            try copyIfMissing(files.appendingPathComponent("ddraw.ini"), to: game.appendingPathComponent("ddraw.ini"))
            try copyIfMissing(files.appendingPathComponent("Shaders/interpolation/catmull-rom-bilinear.glsl"),
                              to: game.appendingPathComponent("Shaders/interpolation/catmull-rom-bilinear.glsl"))
            let ddraw = game.appendingPathComponent("ddraw.dll")
            if sha(ddraw) != sha(files.appendingPathComponent("ddraw.dll")) {
                if FileManager.default.fileExists(atPath: ddraw.path) { try FileManager.default.removeItem(at: ddraw) }
                try FileManager.default.copyItem(at: files.appendingPathComponent("ddraw.dll"), to: ddraw)
            }
            for name in ["RA2.INI", "RA2MD.INI"] {
                try edit(game.appendingPathComponent(name)) { text in
                    var t = text
                    for (key, value) in [("ScreenWidth", String(min(max(context.width, 800), 1920))),
                                         ("ScreenHeight", String(min(max(context.height, 600), 1200))),
                                         ("VideoBackBuffer", "no"), ("AllowHiResModes", "yes")] {
                        t = INIFile.set(in: t, section: "Video", key: key, value: value, onlyIfMissing: true)
                    }
                    return t
                }
            }
        case "witcher3":
            // A proxy that refuses the stream-output pipelines Apple's shader converter cannot build.
            try swapIn(files.appendingPathComponent("amd_fidelityfx_loader_dx12.dll"),
                       at: game.appendingPathComponent("bin/x64_dx12/amd_fidelityfx_loader_dx12.dll"),
                       expectedOriginalSHA: witcherSHA, keepOriginalAs: "amd_fidelityfx_loader_dx12_orig.dll")
        case "heroes3":
            try swapIn(files.appendingPathComponent("xdd.dll"), at: game.appendingPathComponent("xdd.dll"), expectedOriginalSHA: heroesSHA)
            let ini = game.appendingPathComponent("ddraw.ini")
            if !FileManager.default.fileExists(atPath: ini.path) { try FileManager.default.copyItem(at: files.appendingPathComponent("ddraw.ini"), to: ini) }
            let mss = game.appendingPathComponent("MSS32.DLL")
            if let data = try? Data(contentsOf: mss) {
                let fixed = try HeroesAudio.repair(data, originalSHA: heroesAudioSHAs.0, fixedSHA: heroesAudioSHAs.1)
                if fixed != data {
                    try data.write(to: game.appendingPathComponent("MSS32.DLL.macgames-backup"))
                    try fixed.write(to: mss, options: .atomic)
                }
            }
        default:
            break
        }
    }
}
