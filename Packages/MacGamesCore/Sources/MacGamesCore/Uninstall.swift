import Foundation

extension GameRuntime {
    /// Steam's per-game files besides the install folder and the manifest.
    var steamLeftovers: [URL] {
        let id = profile.steamAppID
        return ["shadercache/\(id)", "workshop/content/\(id)", "workshop/appworkshop_\(id).acf", "downloading/\(id)", "temp/\(id)"]
            .map { paths.steamapps.appendingPathComponent($0) }
    }

    /// Bytes on disk that uninstalling frees.
    public func installedSize() throws -> UInt64 {
        let parts = profile.launch == .battleNet ? [paths.installDir] : [paths.installDir] + steamLeftovers
        return parts.reduce(0) { $0 + Self.allocatedSize(of: $1) } + Self.allocatedSize(of: paths.graphics)
    }

    /// Bytes on disk of the whole environment: launcher, Windows files and engine.
    public func environmentSize() throws -> UInt64 { Self.allocatedSize(of: paths.root) }

    /// Deletes the game's files. Saves, settings and the launcher account stay. A Steam game
    /// goes with Steam closed, so Steam cannot write its manifest back; a Battle.net game
    /// goes through Blizzard's own uninstaller.
    public func uninstall() throws {
        if let playing = runningGameTitle() { throw SetupError("Close \(playing) first.") }
        if profile.launch == .battleNet { try uninstallThroughBattleNet(); return }
        if isSessionRunning() {
            progress("Closing Steam…")
            try stop()
        }
        progress("Deleting \(profile.title)…")
        for item in [paths.installDir, paths.appManifest] + steamLeftovers where Self.exists(item) {
            try fm.removeItem(at: item)
        }
        try clearCaches()
        // The online clients live in the install folder, so their setup starts over.
        if Self.exists(cncnetReady) { try fm.removeItem(at: cncnetReady) }
        progress("Uninstalled \(profile.title).")
    }

    /// Deletes shader caches built for the old install, and keeps the folders DXMT writes into.
    func clearCaches() throws {
        guard Self.exists(paths.graphics) else { return }
        try fm.removeItem(at: paths.graphics)
        if profile.graphics == .dxmt {
            for folder in ["shader-cache", "game-archives", "recipes"] {
                try fm.createDirectory(at: paths.graphics.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
        }
    }

    func uninstallThroughBattleNet() throws {
        let registry = (try? String(contentsOf: paths.prefix.appendingPathComponent("system.reg"), encoding: .utf8)) ?? ""
        guard let command = UninstallEntry.command(inSystemRegistry: registry, installDir: paths.windowsPath(paths.installDir)) else {
            try openBattleNet()
            progress("Uninstall \(profile.title) in Battle.net: select it, open the menu next to Play, and choose Uninstall.")
            return
        }
        try startDetached(command, environment: try launchEnvironment(), workingDirectory: driveC, log: "battlenet-session.log")
        try clearCaches()
        progress("Blizzard's uninstaller is open. Confirm there to delete \(profile.title).")
    }

    /// The first game of the environment that has files installed, even partly.
    var installedGame: GameProfile? {
        paths.environment.games.first { game in
            let state = GameState.derive(GamePaths(profile: game, root: paths.root), sessionRunning: false)
            return ![.notSetUp, .needsSteam, .needsGame].contains(state)
        }
    }

    /// The environment is set up and none of its games is installed.
    public var canRemoveEnvironment: Bool { Self.exists(paths.runtimeReady) && installedGame == nil }

    /// Deletes the environment's folder: its launcher, Windows files, engine and packs.
    /// Every game of the environment must be uninstalled first, so no game is lost by accident.
    public func removeEnvironment() throws {
        if let installed = installedGame { throw SetupError("Uninstall \(installed.title) first. Removing the setup deletes every game in \(paths.environment.group).") }
        if isSessionRunning() { try stop() }
        progress("Removing the \(paths.environment.group) setup…")
        if Self.exists(paths.root) { try fm.removeItem(at: paths.root) }
        progress("Removed the \(paths.environment.group) setup.")
    }

    static func exists(_ url: URL) -> Bool {
        (try? url.checkResourceIsReachable()) == true || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Disk use of a file or folder, counting each file's allocated blocks.
    static func allocatedSize(of url: URL) -> UInt64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return 0 }
        guard values.isDirectory == true else { return UInt64(values.totalFileAllocatedSize ?? 0) }
        var total: UInt64 = 0
        let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
        while let file = files?.nextObject() as? URL {
            total += UInt64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Reads the uninstall commands that Windows installers register.
public enum UninstallEntry {
    /// The registered uninstall command of the program installed in `installDir`, as arguments.
    /// `inSystemRegistry` is the text of the prefix's `system.reg`.
    public static func command(inSystemRegistry text: String, installDir: String) -> [String]? {
        var inUninstall = false
        var location: String?, command: String?
        let wanted = normalized(installDir)
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("[") {
                if inUninstall, let command, location.map(normalized) == wanted { return split(command) }
                inUninstall = line.contains(#"\\Windows\\CurrentVersion\\Uninstall\\"#)
                location = nil; command = nil
                continue
            }
            guard inUninstall else { continue }
            if let v = value(line, named: "InstallLocation") { location = v }
            if let v = value(line, named: "UninstallString") { command = v }
        }
        if inUninstall, let command, location.map(normalized) == wanted { return split(command) }
        return nil
    }

    static func normalized(_ path: String) -> String {
        var p = path.lowercased()
        while p.hasSuffix("\\") { p.removeLast() }
        return p
    }

    /// The text of a `"Name"="value"` line, with Wine's `\\`, `\"` and `\x…` escapes undone.
    static func value(_ line: Substring, named name: String) -> String? {
        let start = "\"\(name)\"=\""
        guard line.hasPrefix(start), line.hasSuffix("\""), line.count > start.count else { return nil }
        var out = "", rest = Substring(line.dropFirst(start.count).dropLast())
        while let c = rest.popFirst() {
            guard c == "\\", let next = rest.popFirst() else { out.append(c); continue }
            if next == "x" {
                let hex = rest.prefix { $0.isHexDigit }.prefix(4)
                rest = rest.dropFirst(hex.count)
                if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) { out.unicodeScalars.append(scalar) }
            } else {
                out.append(next)
            }
        }
        return out
    }

    /// Splits a Windows command line into arguments; quotes group words and are removed.
    static func split(_ line: String) -> [String] {
        var args: [String] = [], current = "", quoted = false, started = false
        for c in line {
            switch c {
            case "\"": quoted.toggle(); started = true
            case " " where !quoted:
                if started { args.append(current) }
                current = ""; started = false
            default: current.append(c); started = true
            }
        }
        if started { args.append(current) }
        return args
    }
}
