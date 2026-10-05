import Foundation
import Testing
@testable import MacGamesCore

@Suite(.serialized) struct UninstallTests {
    let fm = FileManager.default

    func installedSteamGame(_ profile: GameProfile) throws -> FakeEnvironment {
        let env = try FakeEnvironment(profile)
        let p = env.runtime.paths, id = profile.steamAppID
        try env.installSteam()
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"\(id)\"\n\t\"installdir\"\t\t\"\(profile.installFolder)\"\n\t\"StateFlags\"\t\t\"4\"\n}\n", to: p.appManifest)
        try write("exe", to: p.gameExe)
        for leftover in ["shadercache/\(id)/cache.bin", "workshop/content/\(id)/map.bin", "workshop/appworkshop_\(id).acf",
                         "downloading/\(id)/part.bin", "temp/\(id)/tmp.bin"] {
            try write("x", to: p.steamapps.appendingPathComponent(leftover))
        }
        try write("save", to: p.gameData.appendingPathComponent("home/save.dat"))
        try write("cache", to: p.graphics.appendingPathComponent("shader-cache/a.bin"))
        try LaunchSettings(hud: true).save(to: p)
        return env
    }

    @Test func uninstallingDeletesTheGameButKeepsSavesAndSettings() throws {
        let env = try installedSteamGame(.cs2); defer { env.cleanUp() }
        let p = env.runtime.paths
        #expect(try env.runtime.installedSize() > 0)
        try env.runtime.uninstall()
        #expect(!fm.fileExists(atPath: p.installDir.path))
        #expect(!fm.fileExists(atPath: p.appManifest.path))
        for gone in ["shadercache/730", "workshop/content/730", "workshop/appworkshop_730.acf", "downloading/730", "temp/730"] {
            #expect(!fm.fileExists(atPath: p.steamapps.appendingPathComponent(gone).path), "\(gone)")
        }
        #expect(read(p.gameData.appendingPathComponent("home/save.dat")) == "save")
        #expect(LaunchSettings.load(from: p).hud)
        #expect(!fm.fileExists(atPath: p.graphics.appendingPathComponent("shader-cache/a.bin").path), "caches of the old build go too")
        #expect(fm.fileExists(atPath: p.graphics.appendingPathComponent("shader-cache").path), "DXMT still needs its folders")
        #expect(env.runtime.state() == .needsGame)
    }

    @Test func uninstallingWaitsUntilNoGameOfTheEnvironmentRuns() throws {
        let env = try installedSteamGame(.cs2); defer { env.cleanUp() }
        env.live(["RelicCardinal.exe"])
        #expect(throws: SetupError.self) { try env.runtime.uninstall() }
        #expect(fm.fileExists(atPath: env.runtime.paths.gameExe.path))
    }

    @Test func uninstallingClosesSteamFirst() throws {
        let env = try installedSteamGame(.cs2); defer { env.cleanUp() }
        env.live()
        try env.runtime.uninstall()
        let calls = env.calls
        #expect(calls.contains("wineserver -k"), "Steam must not write the manifest back")
    }

    @Test func uninstallingRedAlert2ForgetsItsOnlineSetup() throws {
        let env = try installedSteamGame(.redAlert2); defer { env.cleanUp() }
        try write("", to: env.runtime.cncnetReady)
        try env.runtime.uninstall()
        #expect(!fm.fileExists(atPath: env.runtime.cncnetReady.path))
    }

    static let systemReg = #"""
    WINE REGISTRY Version 2

    [Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Battle.net] 1791205395
    "DisplayName"="Battle.net"
    "UninstallString"="\"C:\\Program Files (x86)\\Battle.net\\Battle.net Uninstaller.exe\""

    [Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\Diablo IV] 1791205395
    #time=1dd54c9e26c1a08
    "DisplayName"="Diablo IV"
    "InstallLocation"="C:\\Program Files (x86)\\Diablo IV"
    "UninstallString"="\"C:\\ProgramData\\Battle.net\\Agent\\Blizzard Uninstaller.exe\" --lang=enUS --uid=fenris --displayname=\"Diablo IV\""

    """#

    @Test func theBlizzardUninstallerIsFoundByInstallFolder() {
        let command = UninstallEntry.command(inSystemRegistry: Self.systemReg, installDir: #"C:\Program Files (x86)\Diablo IV"#)
        #expect(command == [#"C:\ProgramData\Battle.net\Agent\Blizzard Uninstaller.exe"#, "--lang=enUS", "--uid=fenris",
                            "--displayname=Diablo IV"])
        #expect(UninstallEntry.command(inSystemRegistry: Self.systemReg, installDir: #"C:\Program Files (x86)\Overwatch"#) == nil)
    }

    @Test func aBattleNetGameUninstallsThroughBlizzardsUninstaller() throws {
        let env = try FakeEnvironment(.diablo4BattleNet); defer { env.cleanUp() }
        let p = env.runtime.paths
        try write("", to: p.battleNetExe)
        try write("exe", to: p.gameExe)
        try write(Self.systemReg, to: p.prefix.appendingPathComponent("system.reg"))
        try env.runtime.uninstall()
        #expect(env.calls.contains(#"wine C:\ProgramData\Battle.net\Agent\Blizzard Uninstaller.exe --lang=enUS --uid=fenris --displayname=Diablo IV"#))
    }

    @Test func removingAnEnvironmentNeedsAllItsGamesUninstalled() throws {
        let env = try installedSteamGame(.rdr2); defer { env.cleanUp() }
        #expect(!env.runtime.canRemoveEnvironment)
        #expect(throws: SetupError.self) { try env.runtime.removeEnvironment() }
        try env.runtime.uninstall()
        #expect(env.runtime.canRemoveEnvironment)
        #expect(try env.runtime.environmentSize() > 0)
        try env.runtime.removeEnvironment()
        #expect(!fm.fileExists(atPath: env.runtime.paths.root.path))
        #expect(env.runtime.state() == .notSetUp)
        #expect(!env.runtime.canRemoveEnvironment, "nothing is left to remove")
    }
}
