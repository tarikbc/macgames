import Foundation

/// What the display looks like at launch, measured by the app (which has AppKit).
public struct LaunchContext: Sendable, Equatable {
    public struct Size: Sendable, Equatable {
        public let width: Int, height: Int
        public init(width: Int, height: Int) { self.width = width; self.height = height }
    }

    /// Main display size in points.
    public var width: Int
    public var height: Int
    /// The main display has a camera housing at the top.
    public var hasNotch: Bool
    /// The height of the notch area at the top of the main display, in points.
    public var topInset: Double

    public init(width: Int, height: Int, hasNotch: Bool = false, topInset: Double = 0) {
        self.width = width; self.height = height; self.hasNotch = hasNotch; self.topInset = topInset
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

    /// Changes a text file in its own encoding. A file that exists but cannot be read is never written over.
    static func edit(_ url: URL, _ change: (String) -> String) throws {
        let fm = FileManager.default
        var encoding = String.Encoding.utf8
        var old = ""
        if fm.fileExists(atPath: url.path) {
            guard let text = (try? String(contentsOf: url, usedEncoding: &encoding)) ?? (try? String(contentsOf: url, encoding: .utf8)) else {
                throw SetupError("\(url.lastPathComponent) uses a text encoding MacGames cannot read, so it was left unchanged.")
            }
            old = text
        }
        let new = change(old)
        guard new != old else { return }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: url.path + ".macgames-backup") {
            try fm.copyItem(atPath: url.path, toPath: url.path + ".macgames-backup")
        }
        try new.write(to: url, atomically: true, encoding: encoding)
    }

    /// Replaces `original` in place with `replacement`, keeping the original as `<name>_orig`, but only
    /// when the file is the build MacGames expects (or already replaced).
    static func swapIn(_ replacement: URL, at original: URL, expectedOriginalSHA: String?, keepOriginalAs backupName: String? = nil) throws {
        let fm = FileManager.default
        guard let wanted = sha(replacement) else { throw SetupError("MacGames is missing \(replacement.lastPathComponent).") }
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
        try replace(original, with: replacement)
    }

    /// Puts a copy of `source` at `target` in one step, so a failed copy never loses the old file.
    static func replace(_ target: URL, with source: URL) throws {
        let fm = FileManager.default
        let temp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).macgames-new")
        if fm.fileExists(atPath: temp.path) { try fm.removeItem(at: temp) }
        try fm.copyItem(at: source, to: temp)
        if fm.fileExists(atPath: target.path) { _ = try fm.replaceItemAt(target, withItemAt: temp) }
        else { try fm.moveItem(at: temp, to: target) }
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

    /// Steps that only change files, run before each launch. A file from a game build MacGames
    /// does not know is left alone; the returned warnings say which fix was skipped.
    @discardableResult
    public static func prepare(_ profile: GameProfile, paths: GamePaths, runtime: RuntimeLayout, context: LaunchContext,
                               witcherSHA: String? = witcherLoaderSHA, heroesSHA: String? = heroesRendererSHA,
                               heroesAudioSHAs: (String?, String?) = (HeroesAudio.originalSHA, HeroesAudio.fixedSHA)) throws -> [String] {
        let files = runtime.gameFiles(profile.id)
        let game = paths.installDir
        var warnings: [String] = []
        func skipUnknown(_ fix: () throws -> Void) rethrows {
            do { try fix() } catch let error as SetupError { warnings.append(error.description) }
        }
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
            try swapInOrAdd(files.appendingPathComponent("ddraw.dll"), at: game.appendingPathComponent("ddraw.dll"))
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
            try skipUnknown {
                try swapIn(files.appendingPathComponent("amd_fidelityfx_loader_dx12.dll"),
                           at: game.appendingPathComponent("bin/x64_dx12/amd_fidelityfx_loader_dx12.dll"),
                           expectedOriginalSHA: witcherSHA, keepOriginalAs: "amd_fidelityfx_loader_dx12_orig.dll")
            }
        case "heroes3":
            try skipUnknown {
                try swapIn(files.appendingPathComponent("xdd.dll"), at: game.appendingPathComponent("xdd.dll"),
                           expectedOriginalSHA: heroesSHA, keepOriginalAs: "xdd.dll.macgames-backup")
            }
            let ini = game.appendingPathComponent("ddraw.ini")
            if !FileManager.default.fileExists(atPath: ini.path) { try FileManager.default.copyItem(at: files.appendingPathComponent("ddraw.ini"), to: ini) }
            let mss = game.appendingPathComponent("MSS32.DLL")
            if let data = try? Data(contentsOf: mss) {
                try skipUnknown {
                    let fixed = try HeroesAudio.repair(data, originalSHA: heroesAudioSHAs.0, fixedSHA: heroesAudioSHAs.1)
                    if fixed != data {
                        try data.write(to: game.appendingPathComponent("MSS32.DLL.macgames-backup"))
                        try fixed.write(to: mss, options: .atomic)
                    }
                }
            }
        default:
            break
        }
        return warnings
    }

    /// Like `swapIn` for files the game may not ship at all; keeps one backup of what was there.
    static func swapInOrAdd(_ replacement: URL, at target: URL) throws {
        guard sha(target) != sha(replacement) else { return }
        let backup = URL(fileURLWithPath: target.path + ".macgames-backup")
        if FileManager.default.fileExists(atPath: target.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: target, to: backup)
        }
        try replace(target, with: replacement)
    }
}
