import Foundation
import Testing
@testable import MacGamesCore

@Suite struct WindowsHelperPlanTests {
    let notch = LaunchContext(width: 1512, height: 982, hasNotch: true, topInset: 32)

    @Test func ageOfMythologyKeepsItsGPUKeysAndItsWindowBelowTheNotch() {
        let paths = GamePaths(profile: .aomRetold, root: URL(fileURLWithPath: "/r"))
        let watchers = WindowsHelper.watchers(for: .aomRetold, paths: paths, context: notch)
        #expect(watchers.map(\.name) == ["gpu-sync", "fit-window"])
        #expect(watchers[0].arguments == ["--watch", "AoMRT_s.exe", "--wait-seconds", "300"])
        #expect(watchers[1].arguments == ["--program", "AoMRT_s.exe", "--width", "1512", "--height", "982", "--inset", "32",
                                          "--wait-seconds", "300"])
        let flat = WindowsHelper.watchers(for: .aomRetold, paths: paths, context: LaunchContext(width: 1920, height: 1080))
        #expect(flat.map(\.name) == ["gpu-sync"], "a screen without a notch needs no window fitting")
    }

    @Test func gtaVDismissesOnlyItsExactDriverAdvisory() {
        let paths = GamePaths(profile: .gta5, root: URL(fileURLWithPath: "/r"))
        let watchers = WindowsHelper.watchers(for: .gta5, paths: paths, context: notch)
        #expect(watchers.map(\.name) == ["dismiss-dialog"])
        #expect(watchers[0].arguments == ["--program", "GTA5_Enhanced.exe", "--title", "Minimum Recommended Hardware Check Failure",
                                          "--text", WindowsHelper.gtaAdvisoryText, "--wait-seconds", "600"])
        #expect(WindowsHelper.gtaAdvisoryText.hasPrefix("Please update your graphics driver. Game requires version 24.12.1"))
    }

    @Test func otherGamesStartNoWatchers() {
        for profile in GameProfile.all where !["aom-retold", "gta5-enhanced"].contains(profile.id) {
            #expect(WindowsHelper.watchers(for: profile, paths: GamePaths(profile: profile, root: URL(fileURLWithPath: "/r")),
                                           context: notch).isEmpty, "\(profile.id)")
        }
    }

    @Test func theDisplaySizeIsReadPastWineMessages() {
        #expect(WindowsHelper.displaySize("msync: up and running.\r\n2056 1329\r\n") == LaunchContext.Size(width: 2056, height: 1329))
        #expect(WindowsHelper.displaySize("msync: up and running.\n") == nil)
    }

    @Test func steamCanStartInTheBackgroundAndRestartsForOtherSettings() {
        let paths = GamePaths(profile: .aomRetold, root: URL(fileURLWithPath: "/r"))
        #expect(SteamLaunch.arguments(paths, .background).last == "-silent")
        #expect(SteamLaunch.needsRestart(.background, sessionRunning: true, fingerprintMatches: false))
        #expect(!SteamLaunch.needsRestart(.background, sessionRunning: true, fingerprintMatches: true))
    }
}

@Suite(.serialized) struct WindowsHelperFlowTests {
    func installGame(_ env: FakeEnvironment) throws {
        let p = env.runtime.paths, profile = env.runtime.profile
        try env.installSteam()
        try write("""
        "AppState"
        {
        \t"appid"\t\t"\(profile.steamAppID)"
        \t"installdir"\t\t"\(profile.installFolder)"
        \t"StateFlags"\t\t"4"
        }
        """, to: p.appManifest)
        try write("exe", to: p.gameExe)
        // Rockstar games need their launcher; a stand-in keeps the test off the network.
        try write("", to: p.prefix.appendingPathComponent("drive_c/Program Files/Rockstar Games/Launcher/Launcher.exe"))
        for name in ["gpu-sync", "fit-window", "dismiss-dialog", "show-window", "display-mode", "prepare-pipelines"] {
            try write(name, to: env.runtime.runtime.windowsHelpers.appendingPathComponent("\(name).exe"))
        }
    }

    @Test func watchersStartInTheBackgroundSteamBeforeTheGame() throws {
        let env = try FakeEnvironment(.aomRetold); defer { env.cleanUp() }
        try installGame(env)
        try env.runtime.play(LaunchContext(width: 1512, height: 982, hasNotch: true, topInset: 32))
        let calls = env.calls
        let steam = try #require(calls.firstIndex { $0.contains("-silent") })
        let gpu = try #require(calls.firstIndex { $0.contains(#"C:\macgames\gpu-sync.exe --watch AoMRT_s.exe"#) })
        let fit = try #require(calls.firstIndex { $0.contains(#"C:\macgames\fit-window.exe --program AoMRT_s.exe"#) })
        let game = try #require(calls.firstIndex { $0.contains("-applaunch 1934680") })
        #expect(steam < gpu && gpu < game && fit < game)
        #expect(!calls.contains("wineserver -k"), "the game's launch reuses the Steam the watchers joined")
    }

    @Test func watchersStartAfterARestartAndSurviveTheLaunch() throws {
        let env = try FakeEnvironment(.aomRetold); defer { env.cleanUp() }
        try installGame(env)
        try SteamSession.begin(fingerprint: "old settings", paths: env.runtime.paths, environment: [:])
        env.live()
        try env.runtime.play(LaunchContext(width: 1512, height: 982, hasNotch: true, topInset: 32))
        let calls = env.calls
        let kill = try #require(calls.firstIndex(of: "wineserver -k"))
        let gpu = try #require(calls.firstIndex { $0.contains("gpu-sync.exe") })
        let game = try #require(calls.firstIndex { $0.contains("-applaunch 1934680") })
        #expect(kill < gpu && gpu < game)
        #expect(calls.lastIndex(of: "wineserver -k")! < gpu, "nothing restarts Steam after the watchers start")
    }

    @Test func aRestartedSteamIsAwaitedPastItsOldStartLine() throws {
        let env = try FakeEnvironment(.aomRetold); defer { env.cleanUp() }
        try installGame(env)
        try write("System startup time: an earlier start\n", to: env.runtime.steamConsole)
        try write("", to: env.dir.appendingPathComponent("root/steam-never-starts"))
        try SteamSession.begin(fingerprint: "old settings", paths: env.runtime.paths, environment: [:])
        env.live()
        env.runtime.steamStartTimeout = 1
        try env.runtime.ensureSteamSession()
        #expect(env.events.all.contains { $0.contains("taking long") }, "the old line must not count")
    }

    @Test func aWatcherThatFailsDoesNotStopTheGame() throws {
        let env = try FakeEnvironment(.gta5); defer { env.cleanUp() }
        try installGame(env)
        try write("#!/bin/sh\nexit 10\n", to: env.dir.appendingPathComponent("root/fail-dismiss-dialog"))
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(env.calls.contains { $0.contains("-applaunch 3240220") })
        #expect(env.events.all.contains { $0.contains("dismiss-dialog") })
    }

    @Test func overwatchPreparesRecordedPipelinesBeforeItStarts() throws {
        let env = try FakeEnvironment(.overwatch); defer { env.cleanUp() }
        try installGame(env)
        let graphics = env.runtime.paths.graphics
        try write("recipe", to: graphics.appendingPathComponent("recipes/abc.recipe"))
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        let calls = env.calls
        let prepare = try #require(calls.firstIndex {
            $0 == #"wine C:\macgames\prepare-pipelines.exe "# + graphics.appendingPathComponent("recipes").path + " "
                + graphics.appendingPathComponent("shader-cache").path })
        let game = try #require(calls.firstIndex { $0.contains("-applaunch 2357570") })
        #expect(prepare < game)
    }

    @Test func overwatchWithoutRecipesStartsAtOnce() throws {
        let env = try FakeEnvironment(.overwatch); defer { env.cleanUp() }
        try installGame(env)
        try env.runtime.play(LaunchContext(width: 1512, height: 982))
        #expect(!env.calls.contains { $0.contains("prepare-pipelines") })
    }

    @Test func aRunningBattleNetIsShownInsteadOfStartedAgain() throws {
        let env = try FakeEnvironment(.diablo4BattleNet); defer { env.cleanUp() }
        try installGame(env)
        try write("", to: env.runtime.paths.battleNetExe)
        env.live(["Battle.net.exe"])
        try env.runtime.openBattleNet()
        let calls = env.calls
        #expect(calls.contains(#"wine C:\macgames\show-window.exe Battle.net.exe"#))
        #expect(!calls.contains { $0.contains("Battle.net Launcher.exe") || $0.hasSuffix("Battle.net.exe --in-process-gpu --use-gl=angle --use-angle=d3d11") })
    }
}
