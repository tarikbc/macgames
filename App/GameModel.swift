import AppKit
import CoreGraphics
import Foundation
import MacGamesCore
import Observation

/// UI state for one game. Every blocking runtime call runs off the main actor.
@MainActor @Observable
final class GameModel: Identifiable {
    let profile: GameProfile
    let runtime: GameRuntime
    private(set) var state: GameState = .notSetUp
    private(set) var busy = false
    private(set) var activity: String?
    private(set) var error: String?
    /// Set when an action would end a running game; the view asks first.
    var confirmingStop = false
    var settings: LaunchSettings { didSet { let r = runtime, s = settings; Task.detached { r.settings = s } } }

    nonisolated var id: String { profile.id }

    init(profile: GameProfile) {
        self.profile = profile
        let runtime = GameRuntime(profile: profile, runtime: .inBundle())
        self.runtime = runtime
        self.settings = runtime.settings
        runtime.progress = { [weak self] line in Task { @MainActor in self?.activity = line } }
    }

    func refresh() async {
        guard !busy else { return }
        let r = runtime
        state = await Task.detached { r.state() }.value
    }

    /// The one action that moves this game to its next stage.
    func primaryAction() {
        switch state {
        case .notSetUp: perform("Setting up") { r in try r.prepare(); try r.installSteam(); try r.startSteam(.install) }
        case .needsSteam: perform("Installing Steam") { r in try r.installSteam(); try r.startSteam(.install) }
        case .needsGame: perform("Opening Steam") { r in try r.startSteam(.install) }
        case .installing: perform("Opening Steam") { r in try r.startSteam(.open) }
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

    private func perform(_ label: String, _ work: @escaping @Sendable (GameRuntime) throws -> Void) {
        guard !busy else { return }
        busy = true; error = nil; activity = "\(label)…"
        let r = runtime
        Task {
            let failure: String? = await Task.detached {
                do { try work(r); return nil } catch { return String(describing: error) }
            }.value
            busy = false
            error = failure
            if failure == nil { activity = nil }
            await refresh()
        }
    }
}

extension GameState {
    var summary: String {
        switch self {
        case .notSetUp: "Not set up yet"
        case .needsSteam: "Steam is not installed"
        case .needsGame: "Sign in to Steam and install the game"
        case .installing: "Steam is installing the game"
        case .ready: "Ready to play"
        case .running: "Playing"
        }
    }

    var actionTitle: String {
        switch self {
        case .notSetUp: "Set up"
        case .needsSteam: "Install Steam"
        case .needsGame: "Open Steam"
        case .installing: "Show Steam"
        case .ready: "Play"
        case .running: "Stop"
        }
    }
}
