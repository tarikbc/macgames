import Foundation
import Testing
@testable import MacGamesCore

@Suite struct HiDPITests {
    @Test func olderSettingsAdoptExistingRetinaModeAndKeepAnExplicitChoice() throws {
        let fixture = try FakeEnvironment(.aoe4)
        defer { fixture.cleanUp() }
        let paths = fixture.runtime.paths
        try write(#"{"optimized":true,"hud":true}"#, to: LaunchSettings.url(paths))
        try write(#"""
        WINE REGISTRY Version 2
        [Software\\Wine\\Mac Driver] 123
        "RetinaMode"="Y"
        "LogPixels"=dword:00000060
        """#, to: paths.prefix.appendingPathComponent("user.reg"))
        #expect(fixture.runtime.environmentSettings.hiDPI)
        let settings = LaunchSettings.load(from: paths)
        #expect(settings.optimized && settings.hud)
        try EnvironmentSettings(hiDPI: false).save(to: paths)
        #expect(!fixture.runtime.environmentSettings.hiDPI)
        #expect(fixture.calls.isEmpty, "reading or saving preferences must not start Wine")
    }

    @Test func toggleChangesReachAnAlreadyConfiguredPrefixInBothDirections() throws {
        let fixture = try FakeEnvironment(.aoe4)
        defer { fixture.cleanUp() }
        let game = fixture.runtime
        let env = game.environment(optimized: false, hud: false)
        func imported() throws -> String {
            let data = try Data(contentsOf: fixture.dir.appendingPathComponent("root/imported.reg"))
            return try #require(String(data: data.dropFirst(2), encoding: .utf16LittleEndian))
        }
        try EnvironmentSettings(hiDPI: true).save(to: game.paths)
        try game.ensureRecipes(environment: env)
        #expect(try imported().contains(#""RetinaMode"="Y""#))
        try game.ensureRecipes(environment: env)
        #expect(fixture.calls.filter { $0.hasPrefix("wine reg import") }.count == 1)
        try EnvironmentSettings(hiDPI: false).save(to: game.paths)
        try game.ensureRecipes(environment: env)
        let disabled = try imported()
        #expect(disabled.contains(#""RetinaMode"="N""#))
        #expect(!disabled.contains("LogPixels"))
        #expect(fixture.calls.filter { $0.hasPrefix("wine reg import") }.count == 2)
    }

    @Test func defaultsRemainCompatibleAndUserCanOverrideAnExistingGameRecipe() throws {
        let plain = try FakeEnvironment(.aoe4)
        defer { plain.cleanUp() }
        #expect(!plain.runtime.environmentSettings.hiDPI)
        let retinaGame = try FakeEnvironment(.overwatch)
        defer { retinaGame.cleanUp() }
        #expect(retinaGame.runtime.environmentSettings.hiDPI)
        let values = GameRecipes.ordinaryRegistry(for: retinaGame.runtime.paths.environment)
        #expect(!values.contains(where: WineHiDPI.isRetinaMode), "even the Overwatch default must stay out of ordinary recipes")
        try write(#"""
        [Unrelated]
        "RetinaMode"="Y"
        [Software\\Wine\\Mac Driver] 123
        "RetinaMode"="N"
        """#, to: retinaGame.runtime.paths.prefix.appendingPathComponent("user.reg"))
        #expect(!retinaGame.runtime.environmentSettings.hiDPI)
    }

    @Test func gamesSharingAPrefixReadOnePreferenceAndGameSettingsCannotResetIt() throws {
        let f = try FakeEnvironment(.aoe4); defer { f.cleanUp() }
        let other = GameRuntime(profile: .cs2, root: f.runtime.paths.root, runtime: f.runtime.runtime)
        try EnvironmentSettings(hiDPI: true).save(to: f.runtime.paths)
        #expect(other.environmentSettings.hiDPI)
        other.settings = LaunchSettings(optimized: false, hud: true)
        #expect(f.runtime.environmentSettings.hiDPI)
        try EnvironmentSettings(hiDPI: false).save(to: other.paths)
        #expect(!f.runtime.environmentSettings.hiDPI)
        let perGame = try String(contentsOf: LaunchSettings.url(other.paths), encoding: .utf8)
        #expect(!perGame.contains("hiDPI"), "only environment-settings.json owns the preference")
        #expect(f.calls.isEmpty)
    }

    @Test func differentPrefixesKeepIndependentPreferences() throws {
        let a = try FakeEnvironment(.aoe4); defer { a.cleanUp() }
        let b = try FakeEnvironment(.aoe4); defer { b.cleanUp() }
        try EnvironmentSettings(hiDPI: true).save(to: a.runtime.paths)
        try EnvironmentSettings(hiDPI: false).save(to: b.runtime.paths)
        #expect(a.runtime.environmentSettings.hiDPI)
        #expect(!b.runtime.environmentSettings.hiDPI)
    }

    @Test func migrationPreservesAnUnambiguousPendingGameChoice() throws {
        let f = try FakeEnvironment(.aoe4); defer { f.cleanUp() }
        try write(#"{"optimized":true,"hud":false,"hiDPI":true}"#, to: LaunchSettings.url(f.runtime.paths))
        try write("[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"N\"\n", to: f.runtime.paths.prefix.appendingPathComponent("user.reg"))
        #expect(f.runtime.environmentSettings.hiDPI, "keep the saved pending choice rather than the last applied mode")
        try LaunchSettings(optimized: false).save(to: f.runtime.paths)
        #expect(f.runtime.environmentSettings.hiDPI, "rewriting game settings must first preserve migration")
        #expect(FileManager.default.fileExists(atPath: EnvironmentSettings.url(f.runtime.paths).path))
    }

    @Test func conflictingLegacyChoicesUseThePrefixModeRegardlessOfSelectedGame() throws {
        let f = try FakeEnvironment(.aoe4); defer { f.cleanUp() }
        let other = GamePaths(profile: .cs2, root: f.runtime.paths.root)
        try write(#"{"hiDPI":true}"#, to: LaunchSettings.url(f.runtime.paths))
        try write(#"{"hiDPI":false}"#, to: LaunchSettings.url(other))
        try write("[Software\\\\Wine\\\\Mac Driver]\n\"RetinaMode\"=\"N\"\n", to: other.prefix.appendingPathComponent("user.reg"))
        #expect(!EnvironmentSettings.load(from: f.runtime.paths).hiDPI)
        #expect(!EnvironmentSettings.load(from: other).hiDPI)
        try EnvironmentSettings(hiDPI: true).save(to: other)
        #expect(EnvironmentSettings.load(from: f.runtime.paths).hiDPI, "shared saved choice wins over all legacy files")
    }
}
