import Foundation
import Testing
@testable import MacGamesCore

@Suite struct GameStateTests {
    func stage(_ profile: GameProfile = .aoe4) throws -> GamePaths {
        GamePaths(profile: profile, root: try makeTempDir().appendingPathComponent(profile.id))
    }

    func manifest(_ paths: GamePaths, flags: String) throws {
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"\(paths.profile.steamAppID)\"\n\t\"StateFlags\"\t\t\"\(flags)\"\n\t\"installdir\"\t\t\"\(paths.profile.installFolder)\"\n}\n",
                  to: paths.appManifest)
    }

    @Test func freshRootIsNotSetUp() throws {
        let p = try stage(); defer { try? FileManager.default.removeItem(at: p.root.deletingLastPathComponent()) }
        #expect(GameState.derive(p, sessionRunning: false) == .notSetUp)
    }

    @Test func readyRuntimeWithoutSteamNeedsSteam() throws {
        let p = try stage(); defer { try? FileManager.default.removeItem(at: p.root.deletingLastPathComponent()) }
        try write("runtime-v1\n", to: p.runtimeReady)
        #expect(GameState.derive(p, sessionRunning: false) == .needsSteam)
    }

    @Test func steamWithoutManifestNeedsTheGame() throws {
        let p = try stage(); defer { try? FileManager.default.removeItem(at: p.root.deletingLastPathComponent()) }
        try write("runtime-v1\n", to: p.runtimeReady); try write("exe", to: p.steamExe)
        #expect(GameState.derive(p, sessionRunning: true) == .needsGame)
    }

    @Test func partialManifestIsInstalling() throws {
        let p = try stage(); defer { try? FileManager.default.removeItem(at: p.root.deletingLastPathComponent()) }
        try write("runtime-v1\n", to: p.runtimeReady); try write("exe", to: p.steamExe)
        try manifest(p, flags: "1026")
        #expect(GameState.derive(p, sessionRunning: true) == .installing)
    }

    @Test func installedGameIsReadyThenRunning() throws {
        let p = try stage(); defer { try? FileManager.default.removeItem(at: p.root.deletingLastPathComponent()) }
        try write("runtime-v1\n", to: p.runtimeReady); try write("exe", to: p.steamExe)
        try manifest(p, flags: "4"); try write("game", to: p.gameExe)
        #expect(GameState.derive(p, sessionRunning: false) == .ready)
        try write("AppID 1466860 adding PID 77 as a tracked process \"C:\\x\\RelicCardinal.exe\"\n",
                  to: p.steamDir.appendingPathComponent("logs/gameprocess_log.txt"))
        #expect(GameState.derive(p, sessionRunning: true) == .running)
        #expect(GameState.derive(p, sessionRunning: false) == .ready, "a stale log without a live session is not running")
    }
}

@Suite struct LaunchSettingsTests {
    @Test func defaultsAreOptimizedWithoutHUD() {
        let s = LaunchSettings()
        #expect(s.optimized && !s.hud)
    }

    @Test func roundTripsThroughTheRoot() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = GamePaths(profile: .aoe4, root: dir)
        try LaunchSettings(optimized: false, hud: true).save(to: p)
        #expect(LaunchSettings.load(from: p) == LaunchSettings(optimized: false, hud: true))
    }
}
