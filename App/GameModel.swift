import AppKit
import CoreGraphics
import Foundation
import MacGamesCore
import Observation

/// Games share one Steam and one Wine prefix, so only one task may run at a time.
@MainActor @Observable
final class OperationGate {
    /// The game whose task is running, if any.
    var owner: String?
}

/// UI state for one game. Every blocking runtime call runs off the main actor.
@MainActor @Observable
final class GameModel: Identifiable {
    let profile: GameProfile
    let runtime: GameRuntime
    private(set) var state: GameState = .notSetUp
    /// The shared Wine session (Steam and any game) is alive.
    private(set) var sessionRunning = false
    /// 0...1 while Steam installs or updates this game.
    private(set) var downloadProgress: Double?
    @ObservationIgnored private let gate: OperationGate
    /// This game's task is running.
    var busy: Bool { gate.owner == id }
    /// Any game's task is running; every action waits for it.
    var locked: Bool { gate.owner != nil }
    private(set) var activity: String?
    private(set) var error: String?
    /// The setup stage in progress, and the stages finished in this run.
    private(set) var step: SetupStep?
    private(set) var finishedSteps: Set<SetupStep> = []
    /// Set when an action would end a running game; the view asks first.
    var confirmingStop = false
    /// Saved at once on the main actor, so the file always holds the last change.
    var settings: LaunchSettings { didSet { runtime.settings = settings; refreshOptimization() } }
    /// What the next launch does with the x87 optimization.
    private(set) var optimization: OptimizationStatus = .notApplicable

    nonisolated var id: String { profile.id }

    var steamAvailable: Bool { state != .notSetUp && state != .needsSteam }
    var showsSetupSteps: Bool { step != nil || state == .notSetUp || state == .needsSteam }

    init(profile: GameProfile, gate: OperationGate) {
        self.profile = profile
        self.gate = gate
        let (events, sink) = AsyncStream.makeStream(of: RuntimeEvent.self)
        let runtime = GameRuntime(profile: profile, runtime: .inBundle()) { sink.yield($0) }
        self.runtime = runtime
        self.settings = runtime.settings
        Task { [weak self] in
            for await event in events {
                switch event {
                case .progress(let line): self?.activity = line
                case .step(let next): self?.advance(to: next)
                }
            }
        }
    }

    /// Blocking runtime work runs here, not on the threads Swift uses for async tasks.
    private static let work = DispatchQueue(label: "com.tarikbc.macgames.work", qos: .userInitiated)
    private static let reads = DispatchQueue(label: "com.tarikbc.macgames.reads", qos: .utility, attributes: .concurrent)

    private static func off<T: Sendable>(_ queue: DispatchQueue, _ body: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in queue.async { done.resume(returning: body()) } }
    }

    private func refreshOptimization() {
        let r = runtime
        Task { optimization = await Self.off(Self.reads) { r.optimizationStatus() } }
    }

    func refresh() async {
        guard !locked else { return }
        let r = runtime
        let (state, live, download, optimization) = await Self.off(Self.reads) {
            (r.state(), r.isSessionRunning(), SteamStatus.downloadProgress(r.paths), r.optimizationStatus())
        }
        // An old error no longer describes a game that moved to another stage.
        if state != self.state { error = nil }
        self.optimization = optimization
        self.state = state
        self.sessionRunning = live
        self.downloadProgress = download
    }

    /// The one action that moves this game to its next stage.
    func primaryAction() {
        switch state {
        case .notSetUp:
            finishedSteps = []
            perform("Setting up") { r in try r.prepare(); try r.installLauncher(); try r.openForInstall() }
        case .needsSteam:
            perform("Installing \(launcherName)") { r in try r.installLauncher(); try r.openForInstall() }
        case .needsGame: perform("Opening \(launcherName)") { r in try r.openForInstall() }
        case .installing: openSteam()
        case .ready:
            let context = LaunchContext.mainDisplay()
            perform("Starting \(profile.title)") { r in try r.play(context) }
        case .running: confirmingStop = true
        }
    }

    /// "Steam" or "Battle.net": the client this game's environment uses.
    var launcherName: String { profile.gameEnvironment.launcher == .battleNet ? "Battle.net" : "Steam" }

    func openSteam() { perform("Opening \(launcherName)") { r in try r.openLauncher() } }

    func requestStop() {
        if state == .running { confirmingStop = true } else { stop() }
    }

    func stop() { perform("Stopping") { r in try r.stop() } }
    func resetDisplay() { runtime.resetDisplay(); activity = "The next launch sets the window size again." }
    func showLogs() { NSWorkspace.shared.open(runtime.paths.logs) }
    /// The game's install folder once Steam made it, otherwise the library.
    var dataFolder: URL {
        let folder = runtime.paths.steamapps.appendingPathComponent("common/\(profile.installFolder)")
        return FileManager.default.fileExists(atPath: folder.path) ? folder : runtime.paths.root
    }
    func showData() { NSWorkspace.shared.activateFileViewerSelecting([dataFolder]) }
    func dismissError() { error = nil }

    private func advance(to next: SetupStep) {
        if let current = step { finishedSteps.insert(current) }
        step = next
    }

    private func perform(_ label: String, _ work: @escaping @Sendable (GameRuntime) throws -> Void) {
        guard !locked else { return }
        gate.owner = id; error = nil; activity = "\(label)…"
        let r = runtime
        Task {
            let failure: String? = await Self.off(Self.work) {
                do { try work(r); return nil } catch { return String(describing: error) }
            }
            if failure == nil, let current = step { finishedSteps.insert(current) }
            step = nil
            gate.owner = nil
            error = failure
            if failure == nil { activity = nil }
            await refresh()
        }
    }
}

/// The game list and the selection. New profiles appear here with no other change.
@MainActor @Observable
final class LibraryModel {
    let gate = OperationGate()
    let games: [GameModel]
    /// Remembered between launches.
    var selectedID: String = UserDefaults.standard.string(forKey: "selectedGame")
        .flatMap { id in GameProfile.named(id)?.id } ?? GameProfile.all.first?.id ?? "" {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedGame") }
    }

    init() {
        let gate = self.gate
        games = GameProfile.all.map { GameModel(profile: $0, gate: gate) }
    }

    var selected: GameModel? { games.first { $0.id == selectedID } }
    /// Stopping Steam ends a running game, so that game's page asks first.
    func requestStopSteam() {
        if let playing = games.first(where: { $0.state == .running }) {
            selectedID = playing.id
            playing.confirmingStop = true
        } else {
            selected?.stop()
        }
    }

    /// Steam is shared, so any game can tell whether it runs.
    var steamRunning: Bool { games.contains(where: \.sessionRunning) }

    func select(index: Int) {
        guard games.indices.contains(index) else { return }
        selectedID = games[index].id
    }

    private(set) var steam = SteamStatus(account: nil, downloads: [])
    /// The Steam client's own icon, read from its install once it exists.
    private(set) var steamIcon: NSImage?

    func poll() async {
        let root = GamePaths.defaultRoot()
        while !Task.isCancelled {
            for game in games { await game.refresh() }
            steam = await Task.detached { SteamStatus.read(root: root) }.value
            if steamIcon == nil, let game = games.first {
                steamIcon = NSImage(contentsOf: game.runtime.paths.steamDir.appendingPathComponent("public/steam_tray.ico"))
            }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
