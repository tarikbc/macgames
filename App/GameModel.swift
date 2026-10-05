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
    /// This game's Wine session (Steam and the game) is alive.
    private(set) var sessionRunning = false
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
    var settings: LaunchSettings { didSet { let r = runtime, s = settings; Task.detached { r.settings = s } } }

    nonisolated var id: String { profile.id }

    var steamAvailable: Bool { state != .notSetUp && state != .needsSteam }
    var showsSetupSteps: Bool { step != nil || state == .notSetUp || state == .needsSteam }

    init(profile: GameProfile, gate: OperationGate) {
        self.profile = profile
        self.gate = gate
        let runtime = GameRuntime(profile: profile, runtime: .inBundle())
        self.runtime = runtime
        self.settings = runtime.settings
        runtime.progress = { [weak self] line in Task { @MainActor in self?.activity = line } }
        runtime.stepChanged = { [weak self] next in Task { @MainActor in self?.advance(to: next) } }
    }

    func refresh() async {
        guard !locked else { return }
        let r = runtime
        let (state, live) = await Task.detached { (r.state(), r.isSessionRunning()) }.value
        self.state = state
        self.sessionRunning = live
    }

    /// The one action that moves this game to its next stage.
    func primaryAction() {
        switch state {
        case .notSetUp:
            finishedSteps = []
            perform("Setting up") { r in try r.prepare(); try r.installSteam(); try r.startSteam(.install) }
        case .needsSteam:
            perform("Installing Steam") { r in try r.installSteam(); try r.startSteam(.install) }
        case .needsGame: perform("Opening Steam") { r in try r.startSteam(.install) }
        case .installing: openSteam()
        case .ready:
            let size = CGDisplayBounds(CGMainDisplayID()).size
            perform("Starting \(profile.title)") { r in try r.play(displayWidth: Int(size.width), displayHeight: Int(size.height)) }
        case .running: confirmingStop = true
        }
    }

    func openSteam() { perform("Opening Steam") { r in try r.startSteam(.open) } }

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
            let failure: String? = await Task.detached {
                do { try work(r); return nil } catch { return String(describing: error) }
            }.value
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

    func poll() async {
        while !Task.isCancelled {
            for game in games { await game.refresh() }
            try? await Task.sleep(for: .seconds(3))
        }
    }
}
