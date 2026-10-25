import Foundation
import Testing
@testable import MacGamesCore

@Suite(.serialized) struct SteamHiDPITests {
    /// `true` when an imported `.reg` sets the prefix-wide RetinaMode. Per-executable values
    /// under `AppDefaults\<exe>\Mac Driver`, such as Age of Wonders 4's, do not count.
    func setsPrefixRetinaMode(_ registry: String) -> Bool {
        var section = ""
        for line in registry.components(separatedBy: "\n") {
            if line.hasPrefix("[") { section = line; continue }
            if section == "[\(WineHiDPI.key)]", line.hasPrefix(#""RetinaMode"="#) { return true }
        }
        return false
    }

    func fixture() throws -> FakeEnvironment {
        let fixture = try FakeEnvironment(.cs2)
        try fixture.installSteam()
        fixture.runtime.settings = LaunchSettings(optimized: false)
        try EnvironmentSettings(hiDPI: false).save(to: fixture.runtime.paths)
        let env = try fixture.runtime.launchEnvironment()
        try SteamSession.begin(fingerprint: SteamLaunch.fingerprint(env), paths: fixture.runtime.paths, environment: env)
        try EnvironmentSettings(hiDPI: true).save(to: fixture.runtime.paths)
        return fixture
    }

    @Test func changedDisplayPreferenceRestartsSteamBeforeRegistryImport() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.live()
        try f.runtime.startSteam(.play([]))
        let stop = try #require(f.calls.firstIndex(of: "wineserver -k"))
        let registry = try #require(f.calls.firstIndex { $0.hasPrefix("wine reg import") })
        let launch = try #require(f.calls.firstIndex { $0.contains("-applaunch 730") })
        #expect(stop < registry && registry < launch)
        #expect(try f.runtime.launchEnvironment()["MACGAMES_HIDPI"] == "1")
    }

    @Test func anotherRunningGamePreventsBothRestartAndRegistryMutation() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.live(["RelicCardinal.exe"])
        #expect(throws: SetupError.self) { try f.runtime.startSteam(.play([])) }
        #expect(!f.calls.contains("wineserver -k"))
        #expect(!f.calls.contains { $0.hasPrefix("wine reg import") })
    }

    @Test func openingSteamDefersTheChangeAndPreservesDownloads() throws {
        let f = try fixture(); defer { f.cleanUp() }
        f.live()
        try f.runtime.startSteam(.open)
        #expect(!f.calls.contains("wineserver -k"))
        #expect(f.calls.contains { $0.hasPrefix("wine reg import") }, "ordinary recipes must still update")
        let data = try Data(contentsOf: f.dir.appendingPathComponent("root/imported.reg"))
        let registry = try #require(String(data: data.dropFirst(2), encoding: .utf16LittleEndian))
        #expect(registry.contains("witcher3.exe"), "a real per-executable recipe is applied")
        #expect(registry.contains(#"AOW4.exe\Mac Driver"#), "a per-executable Retina mode is an ordinary recipe")
        #expect(!setsPrefixRetinaMode(registry), "display changes remain deferred")
        #expect(read(f.runtime.hiDPIApplied) == nil)
        let normalMarker = read(f.runtime.paths.root.appendingPathComponent("recipes-applied"))
        try f.runtime.startSteam(.open)
        #expect(f.calls.filter { $0.hasPrefix("wine reg import") }.count == 1, "ordinary recipes cache separately from pending HiDPI")
        try f.runtime.startSteam(.play([]))
        #expect(read(f.runtime.hiDPIApplied) == "1", "the later restart actually applies the deferred choice")
        #expect(read(f.runtime.paths.root.appendingPathComponent("recipes-applied")) == normalMarker)
        let applied = try Data(contentsOf: f.dir.appendingPathComponent("root/imported.reg"))
        let display = try #require(String(data: applied.dropFirst(2), encoding: .utf16LittleEndian))
        #expect(setsPrefixRetinaMode(display))
        #expect(!display.contains("witcher3.exe"), "already applied ordinary recipes need no second import")
    }

    @Test func failedImportDoesNotMarkRecipesOrHiDPIAsApplied() throws {
        let f = try fixture(); defer { f.cleanUp() }
        try write("#!/bin/sh\nexit 7\n", to: f.runtime.paths.wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: f.runtime.paths.wine.path)
        #expect(throws: (any Error).self) {
            try f.runtime.ensureRecipes(environment: [:])
        }
        #expect(read(f.runtime.hiDPIApplied) == nil)
        #expect(read(f.runtime.paths.root.appendingPathComponent("recipes-applied")) == nil)
    }

    @Test func battleNetAlsoRestartsForHiDPIBeforeStartingClient() throws {
        let f = try FakeEnvironment(.diablo4BattleNet); defer { f.cleanUp() }
        try write("", to: f.runtime.paths.battleNetExe)
        try write("0", to: f.runtime.sessionHiDPI)
        f.runtime.settings = LaunchSettings(optimized: false)
        try EnvironmentSettings(hiDPI: true).save(to: f.runtime.paths)
        f.live(["Battle.net.exe"])
        try f.runtime.openBattleNet(play: true)
        let stop = try #require(f.calls.firstIndex(of: "wineserver -k"))
        let registry = try #require(f.calls.firstIndex { $0.hasPrefix("wine reg import") })
        let client = try #require(f.calls.firstIndex { $0.contains("Battle.net.exe") })
        #expect(stop < registry && registry < client)
        #expect(read(f.runtime.sessionHiDPI) == "1")
    }

    @Test func battleNetDoesNotApplyTheChangeWhileItsGameRuns() throws {
        let f = try FakeEnvironment(.diablo4BattleNet); defer { f.cleanUp() }
        try write("", to: f.runtime.paths.battleNetExe)
        try write("0", to: f.runtime.sessionHiDPI)
        f.runtime.settings = LaunchSettings(optimized: false)
        try EnvironmentSettings(hiDPI: true).save(to: f.runtime.paths)
        f.live(["Battle.net.exe", f.runtime.profile.executableName])
        #expect(throws: SetupError.self) { try f.runtime.openBattleNet(play: true) }
        #expect(!f.calls.contains("wineserver -k"))
        #expect(!f.calls.contains { $0.hasPrefix("wine reg import") })
    }
}
