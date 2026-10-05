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
    /// Reads the live Wine processes under a folder; tests replace it.
    var processes: @Sendable (URL) -> ProcessSnapshot = { ProcessSnapshot.take(under: $0) }
    /// How long a started launcher gets before an early exit counts as a failure.
    var startupGrace: TimeInterval = 2
    var steamStartTimeout: TimeInterval = 90
    /// The main display's size in points, where a fullscreen game opens; tests replace it.
    var mainDisplay: @Sendable () -> OverwatchDisplay.Size? = { OverwatchDisplay.mainDisplay() }
    /// The displays as a new Wine session takes them in; tests replace it.
    var displaySignature: @Sendable () -> String? = { OverwatchDisplay.displaySignature() }

    public init(profile: GameProfile, root: URL? = nil, runtime: RuntimeLayout,
                downloadCache: URL = GamePaths.sharedDownloads(),
                events: @escaping @Sendable (RuntimeEvent) -> Void = { _ in }) {
        self.profile = profile
        self.paths = GamePaths(profile: profile, root: root ?? GamePaths.defaultRoot(for: profile.gameEnvironment))
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

    /// The game's stage; pass one `snapshot` to answer many games from a single process scan.
    public func state(using snapshot: ProcessSnapshot? = nil) -> GameState {
        let live = snapshot ?? processes(paths.engine)
        return GameState.derive(paths, sessionRunning: isSessionRunning(using: live),
                                gameProcessRunning: live.isRunning(executable: profile.executableName, under: paths.engine))
    }

    // MARK: Setup

    @discardableResult
    public func check() throws -> HostReport {
        let os = ProcessInfo.processInfo.operatingSystemVersion, need = profile.minimumMacOS
        if os.majorVersion < need[0] || (os.majorVersion == need[0] && os.minorVersion < need[1]) {
            throw SetupError("\(profile.title) needs macOS \(need[0]).\(need[1]) or later.")
        }
        return try HostCheck(runtime: runtime, runner: runner).run(for: profile)
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
        try ensureTemplate()

        for pack in paths.environment.packs {
            progress("Getting the \(pack) pack…")
            try Packs.install(pack, paths: paths, downloader: downloader, runner: runner)
        }

        stepChanged(.engine)
        progress("Installing the Wine engine…")
        try ensureEngine()
        ensureSandbox()
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
        try PrefixSetup.apply(PrefixSetup.graphicsCopies(for: paths))
        try PrefixSetup.mapRootDrives(paths: paths)
        if paths.environment.sdlControllers {
            for command in PrefixSetup.wineBusCommands {
                try runWine(command, environment: plain, timeout: 120)
            }
        }
        try ensureRecipes(environment: plain)
        try runner.run(paths.wineserver, ["-w"], environment: plain, timeout: 120)
        for game in paths.environment.games where game.graphics == .dxmt {
            let gamePaths = GamePaths(profile: game, root: paths.root)
            // A game prepared for the first time also gets its window fitted on first launch.
            let firstTime = !fm.fileExists(atPath: gamePaths.graphics.path)
            for folder in ["shader-cache", "game-archives", "recipes"] {
                try fm.createDirectory(at: gamePaths.graphics.appendingPathComponent(folder), withIntermediateDirectories: true)
            }
            if firstTime { fm.createFile(atPath: gamePaths.gameData.appendingPathComponent("display-pending").path, contents: nil) }
        }
        // Battle.net's installer opens the client in this environment, and the game may start from there.
        if profile.id == "overwatch" { try prepareOverwatch(pipelines: false) }
        try Data(paths.environment.id.utf8).write(to: paths.root.appendingPathComponent(Self.environmentMarker), options: .atomic)
        try Data("runtime-v1\n".utf8).write(to: paths.runtimeReady, options: .atomic)
        progress("The Windows environment is ready.")
    }

    /// Gets the Sikarugir template: the engine's libraries and D3DMetal. A self-contained engine needs none.
    func ensureTemplate() throws {
        guard paths.environment.usesTemplate else { return }
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
    }

    /// Installs the environment's launcher client: Steam, plus the Rockstar
    /// Games Launcher where Rockstar games need it, or the Battle.net client.
    public func installLauncher() throws {
        if paths.environment.launcher == .battleNet { try installBattleNet(); return }
        try installSteam()
        if ["rockstar", "gta5"].contains(paths.environment.id) { try installRockstarLauncher() }
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
            try runWine([try stage(installer), "/S"], environment: env, timeout: 300)
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
        // A newer app may pin newer packs; fetch them before the engine marker is compared.
        for pack in paths.environment.packs {
            try Packs.install(pack, paths: paths, downloader: downloader, runner: runner)
        }
        guard try EngineInstaller(runtime: runtime).install(for: paths) else { return }
        if fm.fileExists(atPath: paths.prefix.appendingPathComponent("drive_c/windows").path) {
            try PrefixSetup.apply(PrefixSetup.graphicsCopies(for: paths))
        }
    }

    /// Runs a Wine command. On a timeout it stops the whole session: killing
    /// only the direct child leaves the rest of Wine's processes running.
    @discardableResult
    func runWine(_ arguments: [String], environment: [String: String], timeout: TimeInterval,
                 allowedStatuses: Set<Int32> = [0]) throws -> String {
        do {
            return try runner.run(paths.wine, arguments, environment: environment, timeout: timeout, allowedStatuses: allowedStatuses)
        } catch let timeout as CommandTimeout {
            _ = try? runner.run(paths.wineserver, ["-k"], environment: environment, timeout: 20, allowedStatuses: [0, 1])
            throw timeout
        }
    }

    /// Notes which settings a Steam that MacGames did not start itself runs with.
    func recordSessionIfRunning(environment: [String: String]) {
        guard isSessionRunning(), SteamSession.load(paths) == nil else { return }
        try? SteamSession.begin(fingerprint: SteamLaunch.fingerprint(environment), paths: paths, environment: environment)
    }

    /// The title of a game of this environment that runs now, Steam-tracked or not.
    func runningGameTitle() -> String? {
        let live = processes(paths.engine)
        for game in paths.environment.games {
            let gamePaths = GamePaths(profile: game, root: paths.root)
            if GameRecipes.processNames(for: game).contains(where: { live.isRunning(executable: $0, under: paths.engine) })
                || (isSessionRunning(using: live) && GameProcessLog.isRunning(game, paths: gamePaths)) {
                return game.title
            }
        }
        return nil
    }

    /// The sandbox folders of every game in this environment; Wine starts with them as HOME and TMPDIR.
    func ensureSandbox() {
        for game in paths.environment.games {
            for folder in GameRecipes.sandboxFolders(for: game, paths: GamePaths(profile: game, root: paths.root)) {
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
            }
        }
    }

    /// Brings registry values and sandbox folders of every game in the environment up to date,
    /// including games added after the environment was first set up.
    func ensureRecipes(environment env: [String: String]) throws {
        ensureSandbox()
        let marker = paths.root.appendingPathComponent("recipes-applied")
        let wanted = GameRecipes.recipeHash(for: paths.environment, root: paths.root)
        guard (try? String(contentsOf: marker, encoding: .utf8)) != wanted else { return }
        let registry = paths.environment.games.flatMap(GameRecipes.registry(for:))
        if !registry.isEmpty { try importRegistry(registry, environment: env) }
        try wanted.write(to: marker, atomically: true, encoding: .utf8)
    }

    /// A process that joins a running session must use the server's sync settings.
    func joined(_ env: [String: String]) -> [String: String] {
        guard isSessionRunning(), let session = SteamSession.load(paths) else { return env }
        return session.join(env)
    }

    // MARK: Steam session

    /// `true` while this game's wineserver is alive. Every Wine process of a
    /// prefix needs its server, so the server's lifetime is the session's.
    public func isSessionRunning(using snapshot: ProcessSnapshot? = nil) -> Bool {
        let server = paths.wineserver.resolvingSymlinksInPath().path
        return (snapshot ?? processes(paths.engine)).paths(under: paths.engine).contains { $0.path == server }
    }

    public func startSteam(_ mode: SteamLaunch.Mode) throws {
        guard fm.fileExists(atPath: paths.runtimeReady.path), fm.fileExists(atPath: paths.steamExe.path) else {
            throw SetupError("Set up Steam first.")
        }
        let wasRunning = isSessionRunning()
        if !wasRunning { try ensureEngine() }
        let env = try launchEnvironment()
        try ensureRecipes(environment: environment(optimized: false, hud: false))
        let fingerprint = SteamLaunch.fingerprint(env)
        var running = wasRunning
        let matches = SteamSession.load(paths)?.fingerprint == fingerprint
        if SteamLaunch.needsRestart(mode, sessionRunning: running, fingerprintMatches: matches) {
            // Every game shares this Steam; restarting it ends whichever one plays.
            if let playing = runningGameTitle() {
                throw SetupError("Close \(playing) first. Steam must restart with \(profile.title)'s settings.")
            }
            progress("Restarting Steam with the current settings…")
            try stop()
            running = false
        }

        let log = paths.logs.appendingPathComponent("steam-session.log")
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        if !running { fm.createFile(atPath: log.path, contents: nil) }
        // A Steam that its installer started has no log yet.
        let handle = try ProcessRunner.appendHandle(for: log)
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
        Thread.sleep(forTimeInterval: startupGrace)
        if !process.isRunning && process.terminationStatus != 0 {
            throw SetupError("Steam exited before it opened (exit \(process.terminationStatus)). Log: \(log.path)")
        }
        if !running { try SteamSession.begin(fingerprint: fingerprint, paths: paths, environment: env) }
        switch mode {
        case .open: progress("Steam is opening.")
        case .background: progress("Steam is starting in the background.")
        case .install, .play: progress("Steam received the request.")
        }
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

// MARK: - Launchers and per-game launch steps

extension Download {
    static let battleNetSetup = Download(
        url: URL(string: "https://www.battle.net/download/getInstallerForGame?os=win&version=LIVE&gameProgram=BATTLENET_APP")!,
        sha256: nil, fileName: "Battle.net-Setup.exe")
    static let rockstarLauncher = Download(
        url: URL(string: "https://gamedownloads.rockstargames.com/public/installer/Rockstar-Games-Launcher.exe")!,
        sha256: nil, fileName: "Rockstar-Games-Launcher.exe")
    static let vcRedist2019 = Download(
        url: URL(string: "https://download.visualstudio.microsoft.com/download/pr/85d47aa9-69ae-4162-8300-e6b7e4bf3cf3/52B196BBE9016488C735E7B41805B651261FFA5D7AA86EB6A1D0095BE83687B2/VC_redist.x64.exe")!,
        sha256: "52b196bbe9016488c735e7b41805b651261ffa5d7aa86eb6a1d0095be83687b2", fileName: "VC_redist.x64.exe")
}

extension GameRuntime {
    static let ucrtbaseSHA = "51cbbde17a768930300236facd9738f54b7801e6715771ff8af90bfbe3fad44f"

    /// Writes all values in one `.reg` file and imports it with a single Wine start.
    func importRegistry(_ values: [RegistryValue], environment: [String: String]) throws {
        let file = paths.prefix.appendingPathComponent("drive_c/macgames-registry-\(UUID().uuidString).reg")
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try RegistryFile.data(values).write(to: file, options: .atomic)
        defer { try? fm.removeItem(at: file) }
        try runWine(["reg", "import", paths.windowsPath(file)], environment: joined(environment), timeout: 120)
    }

    /// Starts a process that keeps running after this call, with its output appended to `log`.
    /// With `mustKeepRunning` false, a quick exit with an error is not a failure: such a program
    /// hands its work to one that already runs.
    func startDetached(_ arguments: [String], environment: [String: String], workingDirectory: URL, log name: String,
                       mustKeepRunning: Bool = true) throws {
        try fm.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let log = paths.logs.appendingPathComponent(name)
        let handle = try ProcessRunner.appendHandle(for: log)
        let process = Process()
        process.executableURL = paths.wine
        process.arguments = arguments
        process.environment = joined(environment)
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        try handle.close()
        Thread.sleep(forTimeInterval: startupGrace)
        if mustKeepRunning && !process.isRunning && process.terminationStatus != 0 {
            throw SetupError("\(arguments.first ?? "The program") exited at once (exit \(process.terminationStatus)). Log: \(log.path)")
        }
    }

    var driveC: URL { paths.prefix.appendingPathComponent("drive_c") }

    /// Copies a program into `C:\macgames` and returns its Windows path. Environments that point
    /// `z:` at their own root reach files outside the prefix only through Wine's fallback for Unix paths.
    func stage(_ file: URL) throws -> String {
        let folder = driveC.appendingPathComponent("macgames")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(file.lastPathComponent)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.copyItem(at: file, to: target)
        return paths.windowsPath(target)
    }

    // MARK: Battle.net

    var battleNetInstallerRunning: Bool { processes(paths.engine).isRunning(executable: "Battle.net-Setup.exe", under: paths.engine) }

    func installBattleNet() throws {
        guard !fm.fileExists(atPath: paths.battleNetExe.path) else { return }
        guard !battleNetInstallerRunning else { progress("The Battle.net installer is still running."); return }
        progress("Getting the Battle.net installer…")
        let installer = try downloader.fetch(.battleNetSetup)
        try startDetached([try stage(installer), "--lang=enUS"] + GameRecipes.battleNetFlags(for: paths.environment),
                          environment: try launchEnvironment(),
                          workingDirectory: driveC, log: "battlenet-session.log")
        progress("The Battle.net installer is open. Sign in when it finishes, then install the game there.")
    }

    /// Opens Battle.net. With `play`, Battle.net also starts the game, for games with a product code.
    public func openBattleNet(play: Bool = false) throws {
        guard fm.fileExists(atPath: paths.battleNetExe.path) else { try installBattleNet(); return }
        let request = play ? profile.battleNetProduct.map { ["--exec=launch \($0)"] } ?? [] : []
        let client = [paths.windowsPath(paths.battleNetExe)] + GameRecipes.battleNetFlags(for: paths.environment) + request
        let folder = paths.battleNetExe.deletingLastPathComponent()
        let live = processes(paths.engine)
        var clientRunning = live.isRunning(executable: "Battle.net.exe", under: paths.engine)
        let gameRunning = live.isRunning(executable: profile.executableName, under: paths.engine)
        if profile.id == "overwatch", !gameRunning, isSessionRunning(using: live), displaysChanged(clientRunning: clientRunning) {
            // Wine keeps the displays its session started with; a game started in an older one
            // may find no usable display. Battle.net's update agent can keep that session alive.
            progress("The displays changed since Battle.net started, so it starts again.")
            try stop()
            clientRunning = false
        }
        if clientRunning {
            if !request.isEmpty {
                // A second start hands the request to the running client, then exits.
                try startDetached(client, environment: try launchEnvironment(), workingDirectory: folder, log: "battlenet-session.log",
                                  mustKeepRunning: false)
                progress("Battle.net is starting \(profile.title).")
                return
            }
            // Battle.net closes to the notification area; starting it again would not show it.
            if showWindow(of: "Battle.net.exe") {
                progress("Battle.net is open. Choose Play there.")
                return
            }
        }
        if !isSessionRunning() { try ensureEngine() }
        try ensureRecipes(environment: environment(optimized: false, hud: false))
        if profile.id == "overwatch", !gameRunning {
            try prepareOverwatch()
        }
        try startDetached(client, environment: try launchEnvironment(), workingDirectory: folder, log: "battlenet-session.log")
        if profile.id == "overwatch", let displays = displaySignature() {
            try? Data(displays.utf8).write(to: sessionDisplays, options: .atomic)
        }
        progress(request.isEmpty ? "Battle.net is opening. Choose Play there." : "Battle.net is opening and will start \(profile.title).")
    }

    /// Opens the environment's launcher window: Battle.net, or Steam.
    public func openLauncher() throws {
        paths.environment.launcher == .battleNet ? try openBattleNet() : try startSteam(.open)
    }

    // MARK: Rockstar

    func installRockstarLauncher() throws {
        let launcher = driveC.appendingPathComponent("Program Files/Rockstar Games/Launcher/Launcher.exe")
        guard !fm.fileExists(atPath: launcher.path) else { return }
        progress("Installing the Rockstar Games Launcher…")
        let installer = try downloader.fetch(.rockstarLauncher)
        try runWine([try stage(installer), "/s", "/f"], environment: try launchEnvironment(), timeout: 600)
    }

    // MARK: Launch

    public func play(_ context: LaunchContext) throws {
        if let blocker = Self.playBlocker(state(), title: profile.title) { throw SetupError(blocker) }
        // Red Alert 2 sizes itself to the display that Windows programs see.
        let context = profile.id == "red-alert2" ? windowsDisplay(context) : context
        restoreKeptSaves()
        for warning in try GameFiles.prepare(profile, paths: paths, runtime: runtime, context: context) { progress(warning) }
        if ["rockstar", "gta5"].contains(paths.environment.id) { try installRockstarLauncher() }
        switch profile.id {
        case "aom-retold":
            // A patched Mac driver keeps the game's fullscreen below the notch.
            try importRegistry([RegistryValue(key: RegistryValue.appDefaults + #"AoMRT_s.exe\Mac Driver"#,
                                              name: "RetoldNotchSafeFullscreen", value: .string(context.hasNotch ? "y" : "n"))],
                               environment: environment(optimized: false, hud: false))
        case "coh3": try ensureCoH3Runtime()
        default: break
        }
        switch profile.launch {
        case .steam:
            try startWatchers(WindowsHelper.watchers(for: profile, paths: paths, context: context))
            try play(displayWidth: context.width, displayHeight: context.height)
        case .direct:
            try ensureSteamReady()
            if profile.id == "elden-ring" { try ensureEldenRingPrerequisites() }
            try launchDirect()
        case .battleNet:
            try openBattleNet(play: true)
        }
    }

    /// Steam must be signed in and idle before a game started outside it can find it.
    func ensureSteamReady() throws {
        guard !isSessionRunning() else { return }
        let before = steamConsoleSize()
        try startSteam(.open)
        waitForSteam(since: before)
    }

    var steamConsole: URL { paths.steamDir.appendingPathComponent("logs/console_log.txt") }

    func steamConsoleSize() -> UInt64 { (try? fm.attributesOfItem(atPath: steamConsole.path)[.size] as? UInt64) ?? 0 }

    /// Waits until Steam's console log, past `before`, shows that Steam finished starting.
    func waitForSteam(since before: UInt64) {
        progress("Waiting for Steam to start…")
        let deadline = Date().addingTimeInterval(steamStartTimeout)
        while Date() < deadline {
            if let handle = try? FileHandle(forReadingFrom: steamConsole) {
                let size = (try? handle.seekToEnd()) ?? 0
                // Steam starts a fresh log on some starts; then everything in it is new.
                try? handle.seek(toOffset: size >= before ? before : 0)
                let fresh = String(decoding: (try? handle.readToEnd()) ?? Data(), as: UTF8.self)
                try? handle.close()
                if fresh.contains("System startup time:") { return }
            }
            Thread.sleep(forTimeInterval: 1)
        }
        progress("Steam is taking long to start; starting the game anyway.")
    }

    func launchDirect() throws {
        let env = try launchEnvironment()
        switch profile.id {
        case "heroes3":
            // Heroes III picks fullscreen only when started from its own folder by cmd.
            let script = driveC.appendingPathComponent("heroes3-fullscreen.cmd")
            try Self.heroesScript(installDir: paths.windowsPath(paths.installDir)).write(to: script, atomically: true, encoding: .utf8)
            try startDetached(["cmd", "/c", paths.windowsPath(script)], environment: env, workingDirectory: driveC, log: "\(profile.id).log")
        default:
            try startDetached([paths.windowsPath(paths.gameExe)] + profile.gameArgs, environment: env,
                              workingDirectory: paths.gameExe.deletingLastPathComponent(), log: "\(profile.id).log")
        }
        progress("\(profile.title) is starting.")
    }

    static func heroesScript(installDir: String) -> String {
        "@echo off\r\ncd /d \"\(installDir)\"\r\nHeroes3.exe\r\n"
    }

    // MARK: Game prerequisites

    /// Elden Ring started directly skips Steam's first-run installers, so they run here once.
    func ensureEldenRingPrerequisites() throws {
        let done = paths.gameData.appendingPathComponent("prerequisites-done")
        guard !fm.fileExists(atPath: done.path) else { return }
        let common = paths.steamapps.appendingPathComponent("common/Steamworks Shared/_CommonRedist")
        let steps: [(String, [String])] = [("vcredist/2019/VC_redist.x86.exe", ["/install", "/quiet", "/norestart"]),
                                           ("vcredist/2019/VC_redist.x64.exe", ["/install", "/quiet", "/norestart"]),
                                           ("DirectX/Jun2010/DXSETUP.exe", ["/silent"])]
        progress("Installing the game's Windows runtimes…")
        for (file, args) in steps {
            let url = common.appendingPathComponent(file)
            guard fm.fileExists(atPath: url.path) else {
                throw SetupError("Let Steam finish downloading Steamworks Common Redistributables, then choose Play again.")
            }
            // 1638: a newer version is already installed; 3010: installed, restart pending.
            try runner.run(paths.wine, [paths.windowsPath(url)] + args, environment: try launchEnvironment(),
                           timeout: 300, allowedStatuses: [0, 1638, 3010])
        }
        try fm.createDirectory(at: paths.gameData, withIntermediateDirectories: true)
        fm.createFile(atPath: done.path, contents: nil)
    }

    /// Company of Heroes 3's multiplayer needs Microsoft's UCRT, scoped to its exe.
    func ensureCoH3Runtime() throws {
        let dll = driveC.appendingPathComponent("windows/system32/ucrtbase.dll")
        let receipt = paths.gameData.appendingPathComponent("ucrtbase-ready")
        if fm.fileExists(atPath: receipt.path), (try? sha256Hex(ofFileAt: dll)) == Self.ucrtbaseSHA { return }
        if let playing = runningGameTitle() {
            throw SetupError("Close \(playing) first. Company of Heroes 3 needs a one-time Windows runtime update.")
        }
        progress("Getting Microsoft's C runtime for multiplayer…")
        let package = try downloader.fetch(.vcRedist2019)
        let stage = paths.root.appendingPathComponent("crt-staging-\(UUID().uuidString)")
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }
        let tar = URL(fileURLWithPath: "/usr/bin/tar")
        var extracted: URL?
        for (i, cab) in CabinetScanner.cabinets(in: try Data(contentsOf: package)).enumerated() {
            let file = stage.appendingPathComponent("payload-\(i).cab")
            try cab.write(to: file)
            let listing = (try? runner.run(tar, ["-tf", file.path], timeout: 30, allowedStatuses: [0, 1])) ?? ""
            guard listing.split(whereSeparator: \.isNewline).contains("a10") else { continue }
            try runner.run(tar, ["-xf", file.path, "-C", stage.path, "a10"], timeout: 60)
            try runner.run(tar, ["-xf", stage.appendingPathComponent("a10").path, "-C", stage.path, "ucrtbase.dll"], timeout: 60)
            extracted = stage.appendingPathComponent("ucrtbase.dll")
            break
        }
        guard let extracted, (try? sha256Hex(ofFileAt: extracted)) == Self.ucrtbaseSHA else {
            throw SetupError("Microsoft's runtime could not be extracted or did not verify.")
        }
        if fm.fileExists(atPath: dll.path) {
            let backup = paths.gameData.appendingPathComponent("ucrtbase.dll.wine")
            if !fm.fileExists(atPath: backup.path) {
                try fm.createDirectory(at: paths.gameData, withIntermediateDirectories: true)
                try fm.copyItem(at: dll, to: backup)
            }
            try fm.removeItem(at: dll)
        }
        try fm.copyItem(at: extracted, to: dll)
        // Every other program keeps Wine's own UCRT; only the game loads Microsoft's.
        try importRegistry([RegistryValue(key: #"HKEY_CURRENT_USER\Software\Wine\DllOverrides"#, name: "ucrtbase", value: .string("builtin")),
                            .dll("RelicCoH3.exe", "ucrtbase", "native,builtin")],
                           environment: environment(optimized: false, hud: false))
        // A running server keeps the old DLL mapped as a known DLL.
        try stop()
        fm.createFile(atPath: receipt.path, contents: nil)
    }
}

/// Finds Microsoft cabinet archives embedded in an installer executable.
public enum CabinetScanner {
    public static func cabinets(in data: Data) -> [Data] {
        let magic: [UInt8] = [0x4D, 0x53, 0x43, 0x46] // "MSCF"
        var found: [Data] = []
        var i = data.startIndex
        while let range = data[i...].firstRange(of: magic) {
            let start = range.lowerBound
            guard start + 12 <= data.endIndex else { break }
            // CFHEADER: reserved1 (4 bytes), then cbCabinet, the cabinet's total size.
            let size = data[(start + 8)..<(start + 12)].reversed().reduce(0) { $0 << 8 | Int($1) }
            if size > 36, start + size <= data.endIndex {
                found.append(data[start..<(start + size)])
                i = start + size
            } else {
                i = start + 4
            }
        }
        return found
    }
}

extension GameRuntime {
    /// Opens the launcher where the user installs this game.
    public func openForInstall() throws {
        paths.environment.launcher == .battleNet ? try openBattleNet() : try startSteam(.install)
    }
}
