import Foundation

/// Runs every setup, launch and stop step for one game.
///
/// All methods block; call them off the main thread.
public final class GameRuntime: @unchecked Sendable {
    public let profile: GameProfile
    public let paths: GamePaths
    public let runtime: RuntimeLayout
    public let downloader: Downloader
    public let runner: ProcessRunner
    public var progress: @Sendable (String) -> Void
    /// Called when setup enters a new stage.
    public var stepChanged: @Sendable (SetupStep) -> Void = { _ in }

    public init(profile: GameProfile, root: URL? = nil, runtime: RuntimeLayout,
                downloadCache: URL = GamePaths.sharedDownloads(),
                progress: @escaping @Sendable (String) -> Void = { _ in }) {
        self.profile = profile
        self.paths = GamePaths(profile: profile, root: root ?? GamePaths.defaultRoot(for: profile))
        self.runtime = runtime
        self.downloader = Downloader(cache: downloadCache)
        self.runner = ProcessRunner(logDirectory: paths.logs)
        self.progress = progress
    }

    var fm: FileManager { .default }
    var cs2DisplayPending: URL { paths.root.appendingPathComponent("cs2-display-pending") }

    public var settings: LaunchSettings {
        get { LaunchSettings.load(from: paths) }
        set { try? newValue.save(to: paths) }
    }

    public func environment(optimized: Bool, hud: Bool) -> [String: String] {
        WineEnvironment.make(profile: profile, paths: paths, inherited: ProcessInfo.processInfo.environment,
                             optimized: optimized, hud: hud, bridge: runtime.bridge)
    }

    /// The environment Steam and the game run with, from the saved settings.
    public func launchEnvironment() throws -> [String: String] {
        let s = settings
        var optimized = s.optimized && profile.optimizedExecutableSHA256 != nil
        if optimized {
            let report = try check()
            optimized = report.optimizationAvailable
            report.notes.forEach(progress)
            for helper in [runtime.bridge, runtime.sidecar] where !fm.isExecutableFile(atPath: helper.path) {
                throw SetupError("The \(helper.lastPathComponent) helper is missing at \(helper.path).")
            }
        }
        return environment(optimized: optimized, hud: s.hud)
    }

    public func state() -> GameState { GameState.derive(paths, sessionRunning: isSessionRunning()) }

    // MARK: Setup

    @discardableResult
    public func check() throws -> HostReport {
        try HostCheck(runtime: runtime, runner: runner).run(for: profile)
    }

    public func prepare() throws {
        stepChanged(.checkMac)
        progress("Checking this Mac…")
        try check()
        guard !isSessionRunning() else { throw SetupError("Close \(profile.title) and its Steam window before setup.") }
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)

        stepChanged(.libraries)
        if !fm.fileExists(atPath: paths.frameworks.path) {
            progress("Getting the graphics and library package (about 87 MB)…")
            let archive = try downloader.fetch(.template)
            progress("Unpacking the graphics and library package…")
            let stage = paths.root.appendingPathComponent("deps-staging-\(UUID().uuidString)")
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: stage) }
            try runner.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-xf", archive.path, "-C", stage.path], timeout: 300)
            let frameworks = stage.appendingPathComponent("Template-1.0.15.app/Contents/Frameworks")
            guard fm.fileExists(atPath: frameworks.appendingPathComponent("renderer/d3dmetal/wine/x86_64-unix/d3d12.so").path) else {
                throw SetupError("The graphics package has an unexpected layout.")
            }
            try fm.createDirectory(at: paths.frameworks.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: frameworks, to: paths.frameworks)
        }

        stepChanged(.engine)
        progress("Installing the Wine engine…")
        try ensureEngine()
        let plain = environment(optimized: false, hud: false)
        progress(try runner.run(paths.wine, ["--version"], environment: plain, timeout: 60).trimmingCharacters(in: .whitespacesAndNewlines))
        try runner.run(paths.wineserver, ["--version"], environment: plain, timeout: 60)

        stepChanged(.windows)
        let systemReg = paths.prefix.appendingPathComponent("system.reg")
        if !fm.fileExists(atPath: systemReg.path) {
            progress("Creating a new Windows environment…")
            try runner.run(paths.wine, ["wineboot", "--init"], environment: plain, timeout: 300)
        }
        // wineboot can return before the server flushes the registry.
        let deadline = Date().addingTimeInterval(90)
        while !fm.fileExists(atPath: systemReg.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.2) }
        guard fm.fileExists(atPath: systemReg.path),
              fm.fileExists(atPath: paths.prefix.appendingPathComponent("drive_c/windows/system32").path) else {
            throw SetupError("Wine did not finish creating the Windows environment. Logs: \(paths.logs.path)")
        }
        stepChanged(.configure)
        progress("Configuring Windows 10, graphics and controllers…")
        try runner.run(paths.wine, ["winecfg", "-v", "win10"], environment: plain, timeout: 120)
        try PrefixSetup.replaceUserLinks(prefix: paths.prefix)
        try PrefixSetup.apply(PrefixSetup.graphicsCopies(for: paths))
        for command in PrefixSetup.wineBusCommands {
            try runner.run(paths.wine, command, environment: plain, timeout: 120)
        }
        try runner.run(paths.wineserver, ["-w"], environment: plain, timeout: 120)

        if profile.graphics == .dxmt {
            for folder in ["shader-cache", "game-archives", "recipes"] {
                try fm.createDirectory(at: paths.graphics.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            if !fm.fileExists(atPath: paths.runtimeReady.path) { fm.createFile(atPath: cs2DisplayPending.path, contents: nil) }
        }
        try Data("runtime-v1\n".utf8).write(to: paths.runtimeReady, options: .atomic)
        progress("The Windows environment is ready.")
    }

    public func installSteam() throws {
        guard fm.fileExists(atPath: paths.runtimeReady.path) else { throw SetupError("Set up the Windows environment first.") }
        stepChanged(.steam)
        if !fm.fileExists(atPath: paths.steamExe.path) {
            progress("Getting the official Steam installer…")
            let installer = try downloader.fetch(.steamSetup)
            progress("SteamSetup.exe SHA-256 \(try sha256Hex(ofFileAt: installer))")
            progress("Installing Steam…")
            try runner.run(paths.wine, [installer.path, "/S"], environment: try launchEnvironment(), timeout: 300)
            guard fm.fileExists(atPath: paths.steamExe.path) else {
                throw SetupError("The Steam installer finished, but steam.exe is missing. Logs: \(paths.logs.path)")
            }
        }
        progress("Steam is installed.")
    }

    /// Installs the current engine. The prefix holds copies of engine and
    /// renderer DLLs, so a new engine re-copies them.
    public func ensureEngine() throws {
        guard try EngineInstaller(runtime: runtime).install(for: paths) else { return }
        if fm.fileExists(atPath: paths.prefix.appendingPathComponent("drive_c/windows").path) {
            try PrefixSetup.apply(PrefixSetup.graphicsCopies(for: paths))
        }
    }

    // MARK: Steam session

    /// `true` while this game's wineserver is alive. Every Wine process of a
    /// prefix needs its server, so the server's lifetime is the session's.
    public func isSessionRunning() -> Bool {
        let server = paths.wineserver.resolvingSymlinksInPath().path
        return LiveProcesses.paths(under: paths.engine).contains { $0.path == server }
    }

    public func startSteam(_ mode: SteamLaunch.Mode) throws {
        guard fm.fileExists(atPath: paths.runtimeReady.path), fm.fileExists(atPath: paths.steamExe.path) else {
            throw SetupError("Set up Steam first.")
        }
        let wasRunning = isSessionRunning()
        if !wasRunning { try ensureEngine() }
        let env = try launchEnvironment()
        let fingerprint = SteamLaunch.fingerprint(env)
        var running = wasRunning
        let matches = SteamSession.load(paths)?.fingerprint == fingerprint
        if SteamLaunch.needsRestart(mode, sessionRunning: running, fingerprintMatches: matches) {
            guard !GameProcessLog.isRunning(profile, paths: paths) else {
                throw SetupError("Close \(profile.title) before you change its launch settings.")
            }
            progress("Restarting Steam with the current settings…")
            try stop()
            running = false
        }

        let log = paths.logs.appendingPathComponent("steam-session.log")
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        if !running { fm.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        try handle.seekToEnd()
        let process = Process()
        process.executableURL = paths.wine
        process.arguments = SteamLaunch.arguments(paths, mode)
        process.environment = env
        process.currentDirectoryURL = paths.steamDir
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        try handle.close()
        Thread.sleep(forTimeInterval: 2)
        if !process.isRunning && process.terminationStatus != 0 {
            throw SetupError("Steam exited before it opened (exit \(process.terminationStatus)). Log: \(log.path)")
        }
        if !running { try SteamSession.begin(fingerprint: fingerprint, paths: paths) }
        progress(mode == .open ? "Steam is opening." : "Steam received the request.")
    }

    public func play(displayWidth: Int? = nil, displayHeight: Int? = nil) throws {
        guard state() == .ready else {
            throw SetupError("\(profile.title) is not ready. Install it in this Steam client's default library first.")
        }
        var extra: [String] = []
        let fixDisplay = profile.id == "cs2" && fm.fileExists(atPath: cs2DisplayPending.path)
        if fixDisplay, let w = displayWidth, let h = displayHeight {
            extra = SteamLaunch.cs2DisplayArguments(width: w, height: h)
        }
        try startSteam(.play(extra))
        if fixDisplay && !extra.isEmpty { try? fm.removeItem(at: cs2DisplayPending) }
    }

    /// Asks the next CS2 launch to apply the borderless window size again.
    public func resetDisplay() {
        fm.createFile(atPath: cs2DisplayPending.path, contents: nil)
    }

    public func stop() throws {
        guard fm.fileExists(atPath: paths.wineserver.path) else { return }
        let env = environment(optimized: false, hud: false)
        try runner.run(paths.wineserver, ["-k"], environment: env, timeout: 20, allowedStatuses: [0, 1])
        try runner.run(paths.wineserver, ["-w"], environment: env, timeout: 30)
        progress("Stopped the \(profile.title) session.")
    }
}
