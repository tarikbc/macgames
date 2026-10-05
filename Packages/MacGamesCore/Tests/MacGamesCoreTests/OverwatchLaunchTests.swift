import Foundation
import Testing
@testable import MacGamesCore

@Suite(.serialized) struct OverwatchLaunchTests {
    let battleNet = #"wine C:\Program Files (x86)\Battle.net\Battle.net.exe --disable-gpu-compositing --from-launcher"#
        + " --in-process-gpu --use-gl=angle --use-angle=swiftshader --force-device-scale-factor=2"

    func installed() throws -> FakeEnvironment {
        let env = try FakeEnvironment(.overwatch)
        let p = env.runtime.paths
        try write("", to: p.battleNetExe)
        try write("exe", to: p.gameExe)
        try write("build", to: p.installDir.appendingPathComponent(".build.info"))
        try FileManager.default.createDirectory(at: p.prefix.appendingPathComponent("drive_c/users/me"), withIntermediateDirectories: true)
        env.runtime.mainDisplay = { OverwatchDisplay.Size(width: 1512, height: 982) }
        return env
    }

    func settings(_ env: FakeEnvironment) -> URL {
        env.runtime.paths.prefix.appendingPathComponent("drive_c/users/me/Documents/Overwatch/Settings/Settings_v0.ini")
    }

    @Test func playSetsTheDisplayAndGraphicsThenAsksBattleNetToStartTheGame() throws {
        let env = try installed(); defer { env.cleanUp() }
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        let p = env.runtime.paths
        let text = try #require(read(settings(env)))
        #expect(OverwatchDisplay.setting(text, section: "[Render.", key: "FullScreenWidth") == "1920")
        #expect(OverwatchDisplay.setting(text, section: "[Render.", key: "FullScreenHeight") == "1200")
        #expect(OverwatchDisplay.setting(text, section: "[Render.", key: "GFXPresetLevel") == "1")
        #expect(read(p.gameData.appendingPathComponent("dxmt.conf"))?.contains("dxgi.fullscreenCanvasHeight = 1200") == true)
        let calls = env.calls
        let pipeline = try #require(calls.firstIndex(of: "ow2-pipeline \(p.gameData.path) "
            + p.engine.appendingPathComponent("lib/wine/game-mode/Overwatch.app").path))
        let client = try #require(calls.firstIndex(of: battleNet + " --exec=launch Pro"))
        #expect(pipeline < client)
    }

    @Test func theNextLaunchKeepsAResolutionChosenInTheGame() throws {
        let env = try installed(); defer { env.cleanUp() }
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        let file = settings(env)
        try write(try #require(read(file)).replacingOccurrences(of: "FullScreenWidth = \"1920\"", with: "FullScreenWidth = \"2560\"")
            .replacingOccurrences(of: "FullScreenHeight = \"1200\"", with: "FullScreenHeight = \"1600\""), to: file)
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(read(env.runtime.paths.gameData.appendingPathComponent("dxmt.conf"))?.contains("dxgi.fullscreenCanvasWidth = 2560") == true)
        #expect(OverwatchDisplay.setting(try #require(read(file)), section: "[Render.", key: "WindowedHeight") == "1600")
    }

    @Test func aRunningBattleNetOnlyGetsThePlayRequest() throws {
        let env = try installed(); defer { env.cleanUp() }
        env.live(["Battle.net.exe"])
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(env.calls.contains(battleNet + " --exec=launch Pro"))
        #expect(!env.calls.contains { $0.hasPrefix("ow2-pipeline") })
        #expect(read(settings(env)) == nil)
    }

    @Test func aFailedGraphicsPreparationStillStartsTheGame() throws {
        let env = try installed(); defer { env.cleanUp() }
        try write("", to: env.dir.appendingPathComponent("root/fail-ow2-pipeline"))
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(env.calls.contains(battleNet + " --exec=launch Pro"))
        #expect(env.events.all.contains { $0.contains("skipped") })
    }

    @Test func setupWritesTheDisplayBeforeTheFirstSession() throws {
        let env = try installed(); defer { env.cleanUp() }
        try write("#!/bin/sh\nexit 0\n", to: env.runtime.runtime.rosettaProbe)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: env.runtime.runtime.rosettaProbe.path)
        try FileManager.default.removeItem(at: env.runtime.paths.runtimeReady)
        try env.runtime.prepare()
        let text = try #require(read(settings(env)))
        #expect(OverwatchDisplay.setting(text, section: "[Render.", key: "FullScreenHeight") == "1200")
        #expect(read(env.runtime.paths.gameData.appendingPathComponent("dxmt.conf")) != nil)
        #expect(FileManager.default.fileExists(atPath: OverwatchDisplay.record(env.runtime.paths).path))
        #expect(!env.calls.contains { $0.hasPrefix("ow2-pipeline") }, "pipelines wait for a launch")
    }

    @Test func theCanvasFollowsTheGameWhenItsSettingsCannotBeChanged() throws {
        let env = try installed(); defer { env.cleanUp() }
        // MacGames would pick 1920x1200 (the game's own size comes with a new card record), but a
        // repeated key keeps the file unchanged, so the game opens at 2560x1600.
        let size = OverwatchDisplay.Size(width: 1920, height: 1200)
        try FileManager.default.createDirectory(at: env.runtime.paths.gameData, withIntermediateDirectories: true)
        try JSONEncoder().encode(OverwatchDisplay.Record(chosen: size, wrote: size, gpu: "Apple M3 Max|4203"))
            .write(to: OverwatchDisplay.record(env.runtime.paths))
        try write("[Render.13]\nFullScreenWidth = \"2560\"\nFullScreenWidth = \"2560\"\nFullScreenHeight = \"1600\"\n", to: settings(env))
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        let conf = try #require(read(env.runtime.paths.gameData.appendingPathComponent("dxmt.conf")))
        #expect(conf.contains("dxgi.fullscreenCanvasWidth = 2560") && conf.contains("dxgi.fullscreenCanvasHeight = 1600"))
        #expect(env.calls.contains(battleNet + " --exec=launch Pro"))
    }

    @Test func aDisplayChangeEndsAnIdleSessionBeforeBattleNetStarts() throws {
        let env = try installed(); defer { env.cleanUp() }
        try write("one display", to: env.runtime.paths.gameData.appendingPathComponent("session-displays"))
        env.runtime.displaySignature = { "two displays" }
        env.live(["Battle.net.exe"])
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        let calls = env.calls
        let kill = try #require(calls.firstIndex(of: "wineserver -k"))
        let client = try #require(calls.firstIndex(of: battleNet + " --exec=launch Pro"))
        #expect(kill < client)
        #expect(calls.contains { $0.hasPrefix("ow2-pipeline") }, "a fresh session is prepared")
        #expect(read(env.runtime.paths.gameData.appendingPathComponent("session-displays")) == "two displays")
    }

    @Test func aDisplayChangeNeverEndsARunningGame() throws {
        let env = try installed(); defer { env.cleanUp() }
        try write("one display", to: env.runtime.paths.gameData.appendingPathComponent("session-displays"))
        env.runtime.displaySignature = { "two displays" }
        env.live(["Battle.net.exe", "Overwatch.exe"])
        try env.runtime.openLauncher()
        #expect(!env.calls.contains("wineserver -k"))
    }

    @Test func aHandoffThatExitsWithAnErrorStillCounts() throws {
        let env = try installed(); defer { env.cleanUp() }
        try write("", to: env.dir.appendingPathComponent("root/handoff-exits-1"))
        env.live(["Battle.net.exe"])
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(env.calls.contains(battleNet + " --exec=launch Pro"))
    }

    @Test func openingBattleNetSetsTheDisplayButDoesNotStartTheGame() throws {
        let env = try installed(); defer { env.cleanUp() }
        try env.runtime.openLauncher()
        #expect(env.calls.contains(battleNet))
        #expect(read(env.runtime.paths.gameData.appendingPathComponent("dxmt.conf")) != nil)
    }
}
