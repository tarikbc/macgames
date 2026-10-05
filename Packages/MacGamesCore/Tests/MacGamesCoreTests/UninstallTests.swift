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

@Suite(.serialized) struct UninstallSafetyTests {
    let fm = FileManager.default

    func installed(_ profile: GameProfile) throws -> FakeEnvironment {
        let env = try FakeEnvironment(profile)
        let p = env.runtime.paths
        try env.installSteam()
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"\(profile.steamAppID)\"\n\t\"installdir\"\t\t\"\(profile.installFolder)\"\n\t\"StateFlags\"\t\t\"4\"\n}\n", to: p.appManifest)
        try write("exe", to: p.gameExe)
        return env
    }

    @Test func otherGamesAndUserFilesStay() throws {
        let env = try installed(.cs2); defer { env.cleanUp() }
        let p = env.runtime.paths
        let others = [p.steamapps.appendingPathComponent("shadercache/731/cache.bin"),
                      p.steamapps.appendingPathComponent("common/Age of Empires IV/RelicCardinal.exe"),
                      p.prefix.appendingPathComponent("drive_c/users/crossover/Documents/save.dat")]
        for file in others { try write("keep", to: file) }
        try env.runtime.uninstall()
        for file in others { #expect(read(file) == "keep", "\(file.path)") }
    }

    @Test func savesInsideTheGameFolderAreKeptAndComeBack() throws {
        let env = try installed(.heroes3); defer { env.cleanUp() }
        let p = env.runtime.paths
        try write("castle", to: p.installDir.appendingPathComponent("Games/MyCampaign.CGM"))
        try env.runtime.uninstall()
        #expect(!fm.fileExists(atPath: p.installDir.path))
        // Steam installs the game again; the next launch brings the saves back.
        try write("exe", to: p.gameExe)
        env.runtime.restoreKeptSaves()
        #expect(read(p.installDir.appendingPathComponent("Games/MyCampaign.CGM")) == "castle")
    }

    @Test func redAlert2KeepsItsSavesAndSettings() {
        #expect(GameRecipes.savesInInstallFolder(for: .redAlert2) == ["Saved Games", "RA2MD.INI"])
        #expect(GameRecipes.savesInInstallFolder(for: .heroes3) == ["Games"])
        #expect(GameRecipes.savesInInstallFolder(for: .cs2).isEmpty)
    }

    @Test func aProfileWithoutAnAppIDHasNoSteamLeftovers() throws {
        let env = try FakeEnvironment(GameProfile(id: "x", title: "X", steamAppID: "", installFolder: "X", executableRelativePath: "x.exe"))
        defer { env.cleanUp() }
        #expect(env.runtime.steamLeftovers.isEmpty)
    }

    @Test func removingASetupNeedsTheEnvironmentsOwnRoot() throws {
        let env = try FakeEnvironment(.rdr2); defer { env.cleanUp() }
        // A root that another environment marked as its own.
        try write("battlenet", to: env.runtime.paths.root.appendingPathComponent("macgames-environment"))
        #expect(throws: SetupError.self) { try env.runtime.removeEnvironment() }
        #expect(fm.fileExists(atPath: env.runtime.paths.root.path))
        // A folder that is no MacGames setup at all.
        let stranger = try FakeEnvironment(.rdr2); defer { stranger.cleanUp() }
        try fm.removeItem(at: stranger.runtime.paths.root.appendingPathComponent("macgames-environment"))
        #expect(throws: SetupError.self) { try stranger.runtime.removeEnvironment() }
    }

    @Test func gamesOutsideTheCatalogBlockRemovalButSteamsRuntimesDoNot() throws {
        let env = try FakeEnvironment(.rdr2); defer { env.cleanUp() }
        try env.installSteam()
        let steamapps = env.runtime.paths.steamapps
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"228980\"\n\t\"name\"\t\t\"Steamworks Common Redistributables\"\n}\n",
                  to: steamapps.appendingPathComponent("appmanifest_228980.acf"))
        #expect(env.runtime.canRemoveEnvironment)
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"620\"\n\t\"name\"\t\t\"Portal 2\"\n}\n", to: steamapps.appendingPathComponent("appmanifest_620.acf"))
        #expect(!env.runtime.canRemoveEnvironment)
        #expect(throws: SetupError.self) { try env.runtime.removeEnvironment() }
    }
}
