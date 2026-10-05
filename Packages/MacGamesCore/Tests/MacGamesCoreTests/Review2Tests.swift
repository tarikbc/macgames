import Foundation
import Testing
@testable import MacGamesCore

@Suite struct RestartGuardTests {
    @Test func onlineClientsCountAsRunningGames() {
        #expect(GameRecipes.processNames(for: .zeroHour).contains("GeneralsOnlineZH.exe"))
        #expect(GameRecipes.processNames(for: .redAlert2).contains("gamemd-spawn.exe"))
        #expect(GameRecipes.processNames(for: .heroes3) == ["Heroes3.exe"])
    }
}

@Suite struct FingerprintScopeTests {
    @Test func sandboxFoldersAndAppIDsChangeTheFingerprint() {
        let a = ["WINEPREFIX": "/p", "HOME": "/r/games/aoe3/home"]
        let b = ["WINEPREFIX": "/p", "HOME": "/r/games/aom-retold/home"]
        #expect(SteamLaunch.fingerprint(a) != SteamLaunch.fingerprint(b))
        #expect(SteamLaunch.fingerprint(["SteamAppId": "1"]) != SteamLaunch.fingerprint(["SteamAppId": "2"]))
    }

    @Test func unrelatedShellKeysStillDoNot() {
        #expect(SteamLaunch.fingerprint(["WINEPREFIX": "/p", "TERM": "x", "PWD": "/a"]) == SteamLaunch.fingerprint(["WINEPREFIX": "/p"]))
    }
}

@Suite struct SessionJoinTests {
    @Test func aProcessJoiningASessionUsesTheServersSyncMode() {
        let session = SteamSession(fingerprint: "f", gameLogOffset: 0, serverKeys: ["WINEMSYNC": "0", "WINEESYNC": "0"])
        let env = session.join(["WINEMSYNC": "1", "WINEESYNC": "0", "HOME": "/h"])
        #expect(env["WINEMSYNC"] == "0")
        #expect(env["HOME"] == "/h")
    }

    @Test func oldSessionRecordsStillLoad() throws {
        let data = Data(#"{"fingerprint":"f","gameLogOffset":3}"#.utf8)
        let s = try JSONDecoder().decode(SteamSession.self, from: data)
        #expect(s.serverKeys == nil)
        #expect(s.join(["WINEMSYNC": "1"])["WINEMSYNC"] == "1")
    }
}

@Suite struct SafeEditTests {
    @Test func utf16FilesAreEditedInTheirOwnEncoding() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("a.ini")
        try "[Video]\r\nScreenWidth=640\r\n".write(to: url, atomically: true, encoding: .utf16)
        try GameFiles.edit(url) { INIFile.set(in: $0, section: "Video", key: "AllowHiResModes", value: "yes") }
        var used = String.Encoding.utf8
        let text = try String(contentsOf: url, usedEncoding: &used)
        #expect(used == .utf16 || used == .utf16LittleEndian || used == .utf16BigEndian)
        #expect(text.contains("ScreenWidth=640\r\nAllowHiResModes=yes"))
    }

    @Test func aFileThatCannotBeReadIsNeverWrittenOver() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("b.ini")
        let bytes = Data([0x5B, 0x41, 0x5D, 0x0A, 0xFF, 0xFE, 0xFD, 0xC3])
        try bytes.write(to: url)
        #expect(throws: SetupError.self) { try GameFiles.edit(url) { $0 + "x=1\n" } }
        #expect(try Data(contentsOf: url) == bytes)
    }

    @Test func aMissingReplacementNeverRemovesTheOriginal() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let original = dir.appendingPathComponent("x.dll")
        try write("game", to: original)
        #expect(throws: (any Error).self) {
            try GameFiles.swapIn(dir.appendingPathComponent("missing.dll"), at: original, expectedOriginalSHA: nil)
        }
        #expect(read(original) == "game")
    }
}

@Suite struct UnknownBuildTests {
    @Test func anUnknownBuildIsAWarningNotABlock() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .witcher3, root: dir.appendingPathComponent("root"))
        let runtime = RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: dir)
        try write("proxy", to: runtime.gameFiles("witcher3").appendingPathComponent("amd_fidelityfx_loader_dx12.dll"))
        let loader = paths.installDir.appendingPathComponent("bin/x64_dx12/amd_fidelityfx_loader_dx12.dll")
        try write("patched by the game", to: loader)
        let warnings = try GameFiles.prepare(.witcher3, paths: paths, runtime: runtime, context: LaunchContext(width: 1, height: 1))
        #expect(warnings.count == 1)
        #expect(read(loader) == "patched by the game")
    }
}

@Suite struct LeftoverAndPinTests {
    @Test func everyStagingKindIsCleanedUp() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["crt-staging-1", "packs/staging-skyrim-1", "games/red-alert2/cncnet-staging-1", "packs/skyrim", "games/red-alert2/backups"] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        EngineInstaller.removeLeftovers(in: dir)
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("crt-staging-1").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("packs/staging-skyrim-1").path))
        #expect(!fm.fileExists(atPath: dir.appendingPathComponent("games/red-alert2/cncnet-staging-1").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("packs/skyrim").path))
        #expect(fm.fileExists(atPath: dir.appendingPathComponent("games/red-alert2/backups").path))
    }

    @Test func everyEnvironmentPackIsPinned() {
        for env in GameEnvironment.all { for pack in env.packs { #expect(Packs.pinned[pack] != nil, "\(pack) has no pin") } }
    }
}

@Suite struct RecipeUpgradeTests {
    /// A fake `wine` that records its arguments, so registry imports can be counted.
    func runtime(_ dir: URL) throws -> (GameRuntime, URL) {
        let game = GameRuntime(profile: .redAlert2, root: dir.appendingPathComponent("steam"),
                               runtime: RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: dir), downloadCache: dir)
        let calls = dir.appendingPathComponent("calls")
        try write("#!/bin/sh\necho \"$@\" >> \"\(calls.path)\"\n", to: game.paths.wine)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: game.paths.wine.path)
        try FileManager.default.createDirectory(at: game.paths.prefix.appendingPathComponent("drive_c"), withIntermediateDirectories: true)
        return (game, calls)
    }

    @Test func newGamesInAnExistingEnvironmentGetTheirRegistryOnce() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let (game, calls) = try runtime(dir)
        try game.ensureRecipes(environment: [:])
        #expect(read(calls)?.components(separatedBy: "reg import").count == 2)
        try game.ensureRecipes(environment: [:])
        #expect(read(calls)?.components(separatedBy: "reg import").count == 2, "unchanged recipes are not imported again")
        #expect(FileManager.default.fileExists(atPath: GamePaths(profile: .witcher3, root: game.paths.root).gameData.appendingPathComponent("home").path))
    }
}

@Suite struct StagedProgramTests {
    @Test func programsAreCopiedIntoDriveCAndRunByTheirWindowsPath() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runtime = GameRuntime(profile: .rdr2, root: dir.appendingPathComponent("root"),
                                  runtime: RuntimeLayout(resources: dir, helpers: dir))
        let installer = dir.appendingPathComponent("SteamSetup.exe")
        try write("v1", to: installer)
        let path = try runtime.stage(installer)
        #expect(path == #"C:\macgames\SteamSetup.exe"#)
        let staged = runtime.driveC.appendingPathComponent("macgames/SteamSetup.exe")
        #expect(read(staged) == "v1")
        try write("v2", to: installer)
        _ = try runtime.stage(installer)
        #expect(read(staged) == "v2", "a newer download replaces the staged copy")
    }
}
