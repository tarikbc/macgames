import Foundation

public enum RuntimeEvent: Sendable {
    case progress(String)
    case step(SetupStep)
}

/// Runs every setup, launch and stop step for one game.
///
/// All methods block; call them off the main thread.
public final class GameRuntime: @unchecked Sendable {
    public let profile: GameProfile
    public let paths: GamePaths
    public let runtime: RuntimeLayout
    public let downloader: Downloader
    public let runner: ProcessRunner
    /// Receives progress lines and setup stages. Set once, at creation.
    let events: @Sendable (RuntimeEvent) -> Void

    public init(profile: GameProfile, root: URL? = nil, runtime: RuntimeLayout,
                downloadCache: URL = GamePaths.sharedDownloads(),
                events: @escaping @Sendable (RuntimeEvent) -> Void = { _ in }) {
        self.profile = profile
        self.paths = GamePaths(profile: profile, root: root ?? GamePaths.defaultRoot())
        self.runtime = runtime
        self.downloader = Downloader(cache: downloadCache)
        self.runner = ProcessRunner(logDirectory: paths.logs)
        self.events = events
    }

    func progress(_ line: String) { events(.progress(line)) }
    func stepChanged(_ step: SetupStep) { events(.step(step)) }

    var fm: FileManager { .default }
    var cs2DisplayPending: URL { paths.gameData.appendingPathComponent("display-pending") }

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
            report.notes.forEach { progress($0) }
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
        EngineInstaller.removeLeftovers(in: paths.root)
        downloader.removePartials()
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
            try runWine(["wineboot", "--init"], environment: plain, timeout: 300)
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
        try runWine(["winecfg", "-v", "win10"], environment: plain, timeout: 120)
        try PrefixSetup.replaceUserLinks(prefix: paths.prefix)
        try PrefixSetup.apply(PrefixSetup.libraryGraphicsCopies(root: paths.root))
        for command in PrefixSetup.wineBusCommands {
            try runWine(command, environment: plain, timeout: 120)
        }
        try runner.run(paths.wineserver, ["-w"], environment: plain, timeout: 120)

        for game in GameProfile.all where game.graphics == .dxmt {
            let gamePaths = GamePaths(profile: game, root: paths.root)
            // A game prepared for the first time also gets its window fitted on first launch.
            let firstTime = !fm.fileExists(atPath: gamePaths.graphics.path)
            for folder in ["shader-cache", "game-archives", "recipes"] {
                try fm.createDirectory(at: gamePaths.graphics.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            if firstTime { fm.createFile(atPath: gamePaths.gameData.appendingPathComponent("display-pending").path, contents: nil) }
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
            let env = try launchEnvironment()
            try runWine([installer.path, "/S"], environment: env, timeout: 300)
            guard fm.fileExists(atPath: paths.steamExe.path) else {
                throw SetupError("The Steam installer finished, but steam.exe is missing. Logs: \(paths.logs.path)")
            }
            // The installer may start Steam itself, with the environment it got.
            _ = try? runner.run(paths.wineserver, ["-w"], environment: env, timeout: 15)
            recordSessionIfRunning(environment: env)
        }
        progress("Steam is installed.")
    }

    /// Installs the current engine. The prefix holds copies of engine and
    /// renderer DLLs, so a new engine re-copies them.
    public func ensureEngine() throws {
        guard try EngineInstaller(runtime: runtime).install(for: paths) else { return }
        if fm.fileExists(atPath: paths.prefix.appendingPathComponent("drive_c/windows").path) {
            try PrefixSetup.apply(PrefixSetup.libraryGraphicsCopies(root: paths.root))
        }
    }

    /// Runs a Wine command. On a timeout it stops the whole session: killing
    /// only the direct child leaves the rest of Wine's processes running.
    @discardableResult
    func runWine(_ arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> String {
        do {
            return try runner.run(paths.wine, arguments, environment: environment, timeout: timeout)
        } catch let timeout as CommandTimeout {
            _ = try? runner.run(paths.wineserver, ["-k"], environment: environment, timeout: 20, allowedStatuses: [0, 1])
            throw timeout
        }
    }

    /// Notes which settings a Steam that MacGames did not start itself runs with.
    func recordSessionIfRunning(environment: [String: String]) {
        guard isSessionRunning(), SteamSession.load(paths) == nil else { return }
        try? SteamSession.begin(fingerprint: SteamLaunch.fingerprint(environment), paths: paths)
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
            // Every game shares this Steam; restarting it ends whichever one plays.
            if let playing = GameProfile.all.first(where: { GameProcessLog.isRunning($0, paths: GamePaths(profile: $0, root: paths.root)) }) {
                throw SetupError("Close \(playing.title) first. Steam must restart with \(profile.title)'s settings.")
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

    /// Why Play cannot start now, in words for the user; `nil` when it can.
    public static func playBlocker(_ state: GameState, title: String) -> String? {
        switch state {
        case .ready: nil
        case .notSetUp: "Set up \(title) first."
        case .needsSteam: "Install Steam first."
        case .needsGame: "Install \(title) in Steam first, in the default folder."
        case .installing: "Wait until Steam finishes the download or update of \(title)."
        case .running: "\(title) is already running."
        }
    }

    public func play(displayWidth: Int? = nil, displayHeight: Int? = nil) throws {
        if let blocker = Self.playBlocker(state(), title: profile.title) { throw SetupError(blocker) }
        var extra: [String] = []
        let fixDisplay = profile.id == "cs2" && fm.fileExists(atPath: cs2DisplayPending.path)
        if fixDisplay, let w = displayWidth, let h = displayHeight {
            // Prefer the game's own settings file; fall back to launch arguments
            // when no Steam account has signed in yet.
            if !(try applyCS2Display(width: w, height: h)) { extra = SteamLaunch.cs2DisplayArguments(width: w, height: h) }
        }
        try startSteam(.play(extra))
        if fixDisplay { try? fm.removeItem(at: cs2DisplayPending) }
    }

    /// Sets CS2 to borderless fullscreen-windowed for the signed-in account and
    /// keeps a copy of the previous file. Returns `false` with no account.
    func applyCS2Display(width: Int, height: Int) throws -> Bool {
        guard let account = SteamAccount.current(paths), account.steamID64 != 0 else { return false }
        let url = CS2VideoConfig.url(paths: paths, account: account)
        let previous = try? String(contentsOf: url, encoding: .utf8)
        if let previous {
            let backups = paths.gameData.appendingPathComponent("display-backups")
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
            try previous.write(to: backups.appendingPathComponent("cs2_video-\(Int(Date().timeIntervalSince1970)).txt"),
                               atomically: true, encoding: .utf8)
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try CS2VideoConfig.apply(to: previous, width: width, height: height).write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    // MARK: Optimization status

    private let statusLock = NSLock()
    private var cachedSidecarSupport: Bool?
    private var cachedExecutable: (size: UInt64, modified: Date, sha: String)?

    /// What the next launch does with the x87 optimization. The game's hash is
    /// cached until the file changes; the sidecar probe runs once per launch.
    public func optimizationStatus() -> OptimizationStatus {
        guard profile.optimizedExecutableSHA256 != nil else { return .notApplicable }
        let enabled = settings.optimized
        statusLock.lock(); defer { statusLock.unlock() }
        var sha: String?
        if let attributes = try? fm.attributesOfItem(atPath: paths.gameExe.path),
           let size = attributes[.size] as? UInt64, let modified = attributes[.modificationDate] as? Date {
            if let cached = cachedExecutable, cached.size == size, cached.modified == modified {
                sha = cached.sha
            } else if let hash = try? sha256Hex(ofFileAt: paths.gameExe) {
                cachedExecutable = (size, modified, hash); sha = hash
            }
        }
        if cachedSidecarSupport == nil {
            cachedSidecarSupport = (try? runner.run(runtime.sidecar, ["--probe"], timeout: 25)) != nil
        }
        return OptimizationStatus.evaluate(profile, enabled: enabled, executableSHA256: sha,
                                           sidecarSupported: cachedSidecarSupport ?? false)
    }

    /// Asks the next CS2 launch to apply the borderless window size again.
    public func resetDisplay() {
        try? fm.createDirectory(at: paths.gameData, withIntermediateDirectories: true)
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
