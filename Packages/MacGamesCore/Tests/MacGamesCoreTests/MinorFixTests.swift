import Foundation
import Testing
@testable import BridgeKit
@testable import MacGamesCore

@Suite struct EngineSwapTests {
    @Test func aFailedSwapPutsTheOldEngineBack() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let engine = dir.appendingPathComponent("engine")
        try write("old", to: engine.appendingPathComponent("bin/wine"))
        #expect(throws: (any Error).self) {
            try EngineInstaller.swap(stage: dir.appendingPathComponent("missing-stage"), into: engine)
        }
        #expect(read(engine.appendingPathComponent("bin/wine")) == "old")
    }

    @Test func leftoversFromACrashAreRemoved() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["engine-staging-A", "engine-old-B", "deps-staging-C", "engine", "prefix"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        EngineInstaller.removeLeftovers(in: dir)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: dir.path)) == ["engine", "prefix"])
    }

    @Test func partialDownloadsAreRemoved() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        try write("x", to: dir.appendingPathComponent(".Template.tar.xz.1234.partial"))
        try write("keep", to: dir.appendingPathComponent("Template.tar.xz"))
        Downloader(cache: dir).removePartials()
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["Template.tar.xz"])
    }
}

@Suite struct RuntimeBehaviourTests {
    func runtime(_ dir: URL, _ profile: GameProfile = .aoe4) -> GameRuntime {
        GameRuntime(profile: profile, root: dir.appendingPathComponent("steam"),
                    runtime: RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: dir.appendingPathComponent("Helpers")),
                    downloadCache: dir.appendingPathComponent("downloads"))
    }

    @Test func aSteamStartedByTheInstallerIsRecorded() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let game = runtime(dir)
        try compileSleeper(to: game.paths.wineserver)
        game.recordSessionIfRunning(environment: ["WINEPREFIX": "/p"])
        #expect(SteamSession.load(game.paths) == nil)
        let p = Process(); p.executableURL = game.paths.wineserver; try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        Thread.sleep(forTimeInterval: 0.2)
        game.recordSessionIfRunning(environment: ["WINEPREFIX": "/p"])
        #expect(SteamSession.load(game.paths)?.fingerprint == SteamLaunch.fingerprint(["WINEPREFIX": "/p"]))
    }

    @Test func aWineTimeoutStopsTheWholeSession() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let game = runtime(dir)
        try compileSleeper(to: game.paths.wine)
        let marker = dir.appendingPathComponent("wineserver-args")
        try write("#!/bin/sh\necho \"$@\" >> \"\(marker.path)\"\n", to: game.paths.wineserver)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.paths.wineserver.path)
        #expect(throws: CommandTimeout.self) { try game.runWine(["wineboot"], environment: [:], timeout: 0.3) }
        #expect(read(marker)?.contains("-k") == true)
    }

    @Test func playExplainsWhatIsMissing() {
        #expect(GameRuntime.playBlocker(.notSetUp, title: "X")?.contains("Set up") == true)
        #expect(GameRuntime.playBlocker(.needsSteam, title: "X")?.contains("Steam") == true)
        #expect(GameRuntime.playBlocker(.needsGame, title: "X")?.contains("Install") == true)
        #expect(GameRuntime.playBlocker(.installing, title: "X")?.contains("download") == true)
        #expect(GameRuntime.playBlocker(.running, title: "X")?.contains("already") == true)
        #expect(GameRuntime.playBlocker(.ready, title: "X") == nil)
    }

    @Test func steamLogIsAppendedNotOverwritten() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let log = dir.appendingPathComponent("steam-session.log")
        for line in ["first\n", "second\n"] {
            let h = try ProcessRunner.appendHandle(for: log); h.write(Data(line.utf8)); try h.close()
        }
        #expect(read(log) == "first\nsecond\n")
    }

    @Test func failuresLeadWithTheLogPath() {
        let f = CommandFailure(executable: "wine", status: 1, output: String(repeating: "x", count: 5000), log: URL(fileURLWithPath: "/l/c.log"))
        #expect(f.description.hasPrefix("wine failed (exit 1). Log: /l/c.log"))
    }
}

@Suite struct OptimizationStatusTests {
    let pin = GameProfile.aoe4.optimizedExecutableSHA256!

    @Test func everyStateHasAClearAnswer() {
        #expect(OptimizationStatus.evaluate(.cs2, enabled: true, executableSHA256: "x", sidecarSupported: true) == .notApplicable)
        #expect(OptimizationStatus.evaluate(.aoe4, enabled: false, executableSHA256: pin, sidecarSupported: true) == .off)
        #expect(OptimizationStatus.evaluate(.aoe4, enabled: true, executableSHA256: nil, sidecarSupported: true) == .waitingForGame)
        #expect(OptimizationStatus.evaluate(.aoe4, enabled: true, executableSHA256: "other", sidecarSupported: true) == .otherBuild)
        #expect(OptimizationStatus.evaluate(.aoe4, enabled: true, executableSHA256: pin, sidecarSupported: false) == .unsupportedRosetta)
        #expect(OptimizationStatus.evaluate(.aoe4, enabled: true, executableSHA256: pin, sidecarSupported: true) == .active)
    }
}

@Suite struct BridgeFallbackTests {
    @Test func aMissingSidecarRunsThePlainLoader() {
        let args = ["/app/Helpers/MacGamesBridge", "--cooperative", "/r/engine/bin/wine", "C:\\RelicCardinal.exe"]
        let env = ["WINEPREFIX": "/r/prefix", Bridge.pinKey: "abc", "AOELAB_SOFTFAULT_GAME": "1"]
        let d = Bridge.decide(arguments: args, environment: env, cwd: "/", isExecutable: { _ in false }) { _ in "abc" }
        guard case let .exec(path, _, unset) = d else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
        #expect(unset.contains("AOELAB_SOFTFAULT_GAME"))
    }
}

@Suite struct CS2VideoConfigTests {
    @Test func existingSettingsBecomeBorderlessFullscreenWindowed() {
        let text = "\"video.cfg\"\n{\n\t\"Version\"\t\t\"16\"\n\t\"setting.fullscreen\"\t\t\"1\"\n\t\"setting.defaultres\"\t\t\"1280\"\n}\n"
        let out = CS2VideoConfig.apply(to: text, width: 2056, height: 1329)
        #expect(out.contains("\t\"setting.fullscreen\"\t\t\"0\"\n"))
        #expect(out.contains("\t\"setting.defaultres\"\t\t\"2056\"\n"))
        for key in ["setting.coop_fullscreen\"\t\t\"1", "setting.nowindowborder\"\t\t\"1", "setting.fullscreen_min_on_focus_loss\"\t\t\"0", "setting.defaultresheight\"\t\t\"1329"] {
            #expect(out.contains(key), "missing \(key)")
        }
        #expect(out.hasSuffix("}\n"))
        #expect(out.components(separatedBy: "setting.fullscreen\"").count == 2, "no duplicate keys")
    }

    @Test func aMissingFileIsSeeded() {
        let out = CS2VideoConfig.apply(to: nil, width: 1728, height: 1117)
        #expect(out.hasPrefix("\"video.cfg\"\n{\n\t\"Version\"\t\t\"16\"\n"))
        #expect(out.contains("\"setting.defaultresheight\"\t\t\"1117\""))
    }

    @Test func theConfigLivesInTheSignedInAccountsFolder() {
        let vdf = "\"users\"\n{\n\t\"76561198000000001\"\n\t{\n\t\t\"PersonaName\"\t\t\"t\"\n\t\t\"MostRecent\"\t\t\"1\"\n\t}\n}\n"
        let account = SteamAccount.parse(vdf)
        #expect(account?.accountID == 39734273)
        let p = GamePaths(profile: .cs2, root: URL(fileURLWithPath: "/r"))
        #expect(CS2VideoConfig.url(paths: p, account: account!).path
                == "/r/prefix/drive_c/Program Files (x86)/Steam/userdata/39734273/730/local/cfg/cs2_video.txt")
    }
}
