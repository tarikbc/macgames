import Foundation
import Testing
@testable import MacGamesCore

@Suite struct RegistryFileTests {
    @Test func rendersVersion5WithStringsAndDwords() {
        let text = RegistryFile.render([
            .init(key: #"HKEY_CURRENT_USER\Software\Wine\AppDefaults\RDR2.exe\DllOverrides"#, name: "dxgi", value: .string("builtin")),
            .init(key: #"HKEY_CURRENT_USER\Software\Wine\AppDefaults\RDR2.exe\DllOverrides"#, name: "d3d12", value: .string("")),
            .init(key: #"HKEY_CURRENT_USER\Software\Microsoft\Avalon.Graphics"#, name: "DisableHWAcceleration", value: .dword(1)),
        ])
        #expect(text == """
        Windows Registry Editor Version 5.00

        [HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\RDR2.exe\\DllOverrides]
        "dxgi"="builtin"
        "d3d12"=""

        [HKEY_CURRENT_USER\\Software\\Microsoft\\Avalon.Graphics]
        "DisableHWAcceleration"=dword:00000001

        """)
    }

    @Test func escapesBackslashesAndQuotesInStrings() {
        let text = RegistryFile.render([.init(key: #"HKEY_CURRENT_USER\Software\GeneralsOnline"#, name: "InstallPath",
                                              value: .string(#"C:\Games\Zero "Hour""#))])
        #expect(text.contains(#""InstallPath"="C:\\Games\\Zero \"Hour\"""#))
    }

    @Test func fileIsUTF16SoNonASCIIPathsSurvive() throws {
        let path = #"C:\users\José\Jogos\Ação"#
        let data = RegistryFile.data([.init(key: #"HKEY_CURRENT_USER\Software\GeneralsOnline"#, name: "InstallPath", value: .string(path))])
        #expect(Array(data.prefix(2)) == [0xFF, 0xFE], "Wine reads a version 5 file as UTF-16LE when it starts with a BOM")
        let text = try #require(String(data: data.dropFirst(2), encoding: .utf16LittleEndian))
        #expect(text.hasPrefix("Windows Registry Editor Version 5.00"))
        #expect(text.contains(RegistryFile.escape(path)))
    }
}

@Suite struct GameRegistryTests {
    func values(_ p: GameProfile) -> [String: String] {
        Dictionary(GameRecipes.registry(for: p).map { ("\($0.key)|\($0.name)", $0.value.text) }, uniquingKeysWith: { $1 })
    }

    @Test func rockstarGamesUseBuiltinsWhileTheLauncherUsesWineD3D() {
        let v = values(.rdr2)
        let app = #"HKEY_CURRENT_USER\Software\Wine\AppDefaults\"#
        #expect(v[app + #"RDR2.exe\DllOverrides|d3d12"#] == "builtin")
        #expect(v[app + #"Launcher.exe\DllOverrides|dxgi"#] == "native,builtin")
        #expect(v[app + #"SocialClubHelper.exe\DllOverrides|d3d12"#] == "")
    }

    @Test func gtaVAddsVulkanForTheWebHelpers() {
        let v = values(.gta5)
        #expect(v[#"HKEY_CURRENT_USER\Software\Wine\AppDefaults\steamwebhelper.exe\DllOverrides|vulkan-1"#] == "native")
        #expect(v[#"HKEY_CURRENT_USER\Software\Wine\AppDefaults\GTA5_Enhanced.exe\DllOverrides|atidxx64"#] == "builtin")
    }

    @Test func witcherAndHeroesAskForWindows11ForTheirExeOnly() {
        #expect(values(.witcher3)[#"HKEY_CURRENT_USER\Software\Wine\AppDefaults\witcher3.exe|Version"#] == "win11")
        #expect(values(.heroes3)[#"HKEY_CURRENT_USER\Software\Wine\AppDefaults\Heroes3.exe|Version"#] == "win11")
    }

    @Test func redAlertLoadsItsDirectDrawWrapperForEveryExe() {
        let v = values(.redAlert2)
        for exe in ["Ra2.exe", "game.exe", "RA2MD.exe", "gamemd.exe", "gamemd-spawn.exe"] {
            #expect(v[#"HKEY_CURRENT_USER\Software\Wine\AppDefaults\"# + exe + #"\DllOverrides|ddraw"#] == "native,builtin")
        }
    }

    @Test func ageOfEmpiresThreeSkipsItsFalseWarnings() {
        let v = values(.aoe3)
        #expect(v[#"HKEY_CURRENT_USER\Software\Microsoft\Microsoft Games\Age of Empires III DE|IgnoreUnsupportedSystem"#] == "1")
        #expect(v[#"HKEY_CURRENT_USER\Software\Microsoft\Microsoft Games\Age of Empires III DE|SystemInitialization"#] == "1")
    }

    @Test func gamesWithoutRegistryNeedsHaveNone() {
        #expect(GameRecipes.registry(for: .aoe4).isEmpty)
    }
}

@Suite struct INIEditTests {
    let crlf = "[Video]\r\nScreenWidth=1024\r\n\r\n[Audio]\r\nVolume=5\r\n"

    @Test func setsAKeyAndKeepsCRLF() {
        let out = INIFile.set(in: crlf, section: "Video", key: "ScreenWidth", value: "1728")
        #expect(out == "[Video]\r\nScreenWidth=1728\r\n\r\n[Audio]\r\nVolume=5\r\n")
    }

    @Test func addsAMissingKeyToItsSection() {
        let out = INIFile.set(in: crlf, section: "Video", key: "AllowHiResModes", value: "yes", onlyIfMissing: true)
        #expect(out.hasPrefix("[Video]\r\nScreenWidth=1024\r\nAllowHiResModes=yes\r\n"))
    }

    @Test func onlyIfMissingKeepsTheUsersValue() {
        #expect(INIFile.set(in: crlf, section: "Video", key: "ScreenWidth", value: "9", onlyIfMissing: true) == crlf)
    }

    @Test func addsAMissingSection() {
        let out = INIFile.set(in: "", section: "SystemSettings", key: "r.WarnOfBadDrivers", value: "0")
        #expect(out == "[SystemSettings]\nr.WarnOfBadDrivers=0\n")
    }

    @Test func spacedKeysMatchToo() {
        let out = INIFile.set(in: "Resolution = 800 600\n", section: nil, key: "Resolution", value: "1728 1117", separator: " = ")
        #expect(out == "Resolution = 1728 1117\n")
    }

    @Test func aByteOrderMarkDoesNotHideTheFirstSection() {
        let out = INIFile.set(in: "\u{FEFF}[Video]\r\nScreenWidth=1024\r\n", section: "Video", key: "ScreenWidth", value: "1728")
        #expect(out == "\u{FEFF}[Video]\r\nScreenWidth=1728\r\n")
    }

    @Test func aCommentAfterTheHeaderKeepsTheSection() {
        let out = INIFile.set(in: "[Video] ; display\nScreenWidth=1024\n", section: "Video", key: "ScreenWidth", value: "1728")
        #expect(out == "[Video] ; display\nScreenWidth=1728\n")
    }

    @Test func mixedLineEndingsStayAndSectionsAreStillFound() {
        let text = "[Game]\r\nA=1\n[Video]\nScreenWidth=1024\r\n"
        #expect(INIFile.set(in: text, section: "Video", key: "ScreenWidth", value: "1728") == "[Game]\r\nA=1\n[Video]\nScreenWidth=1728\r\n")
        #expect(INIFile.set(in: text, section: "Game", key: "B", value: "2") == "[Game]\r\nA=1\nB=2\r\n[Video]\nScreenWidth=1024\r\n")
    }

    @Test func aBracketInsideAValueIsNotASection() {
        let text = "[Video]\nName=[x]y\nScreenWidth=1024\n"
        #expect(INIFile.set(in: text, section: "Video", key: "ScreenWidth", value: "1728") == "[Video]\nName=[x]y\nScreenWidth=1728\n")
    }
}

@Suite struct HeroesAudioTests {
    @Test func theFormatCodeLandsAtItsOffset() throws {
        var original = Data(repeating: 0xCC, count: 0xe500)
        original[0] = 1
        let fixed = try HeroesAudio.repair(original, originalSHA: nil, fixedSHA: nil)
        #expect(Array(fixed[0xe39e..<0xe3d6]) == HeroesAudio.formatCode)
        #expect(fixed[0xe39d] == 0xCC && fixed[0xe3d6] == 0xCC)
        #expect(HeroesAudio.formatCode.count == 0xe3d6 - 0xe39e)
    }

    @Test func anUnknownBuildIsLeftAlone() {
        #expect(throws: SetupError.self) { try HeroesAudio.repair(Data(count: 0xe500)) }
    }
}

@Suite struct SteamArgumentsTests {
    @Test func windowsPathAndGameOptionsFollowTheProfile() {
        let p = GamePaths(profile: .witcher3, root: URL(fileURLWithPath: "/r"))
        #expect(SteamLaunch.arguments(p, .play([])) == [#"C:\Program Files (x86)\Steam\steam.exe"#, "-cef-disable-gpu",
                                                         "-applaunch", "292030", "--launcher-skip"])
    }

    @Test func steamOptionsGoBeforeApplaunch() {
        let p = GamePaths(profile: .hogwarts, root: URL(fileURLWithPath: "/r"))
        #expect(SteamLaunch.arguments(p, .play([])) == [p.steamExe.path, "-cef-disable-gpu", "-no-cef-sandbox", "-applaunch", "990080"])
    }
}

@Suite struct GameProcessTests {
    @Test func aWineGameIsFoundByItsWindowsCommandLine() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let bin = dir.appendingPathComponent("engine/bin/wine-preloader")
        try compileSleeper(to: bin)
        #expect(!LiveProcesses.isRunning(executable: "Game.exe", under: dir.appendingPathComponent("engine")))
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "exec -a 'C:\\Games\\Game.exe' '\(bin.path)'"]
        try p.run(); defer { p.terminate(); p.waitUntilExit() }
        Thread.sleep(forTimeInterval: 0.3)
        #expect(LiveProcesses.isRunning(executable: "game.exe", under: dir.appendingPathComponent("engine")))
        #expect(!LiveProcesses.isRunning(executable: "Other.exe", under: dir.appendingPathComponent("engine")))
    }
}

@Suite struct LauncherStateTests {
    func stage(_ profile: GameProfile) throws -> GamePaths {
        let p = GamePaths(profile: profile, root: try makeTempDir())
        try write("runtime-v1\n", to: p.runtimeReady)
        return p
    }

    @Test func battleNetGamesFollowTheBattleNetClient() throws {
        let p = try stage(.diablo2Resurrected); defer { try? FileManager.default.removeItem(at: p.root) }
        #expect(GameState.derive(p, sessionRunning: false) == .needsSteam)
        try write("bnet", to: p.battleNetExe)
        #expect(GameState.derive(p, sessionRunning: false) == .needsGame)
        try write("exe", to: p.gameExe)
        #expect(GameState.derive(p, sessionRunning: false) == .installing, "no .build.info yet")
        try write("info", to: p.installDir.appendingPathComponent(".build.info"))
        #expect(GameState.derive(p, sessionRunning: false) == .ready)
        #expect(GameState.derive(p, sessionRunning: true, gameProcessRunning: true) == .running)
    }

    @Test func directGamesRunWhenTheirProcessRuns() throws {
        let p = try stage(.eldenRing); defer { try? FileManager.default.removeItem(at: p.root) }
        try write("exe", to: p.steamExe)
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"1245620\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"installdir\"\t\t\"ELDEN RING\"\n}\n", to: p.appManifest)
        try write("game", to: p.gameExe)
        #expect(GameState.derive(p, sessionRunning: true, gameProcessRunning: false) == .ready)
        #expect(GameState.derive(p, sessionRunning: true, gameProcessRunning: true) == .running)
    }
}
