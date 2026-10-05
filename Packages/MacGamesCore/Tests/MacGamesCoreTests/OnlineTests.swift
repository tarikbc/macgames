import Foundation
import Testing
@testable import MacGamesCore

@Suite struct OnlineEnvironmentTests {
    let base = ["WINEDLLOVERRIDES": "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;dxgi,d3d11,d3d12,atidxx64=n,b;nvapi64,nvngx=",
                "WINEDLLPATH": "/r/deps/Frameworks/renderer/d3dmetal/wine:/r/engine/lib/wine", "DOTNET_X": "1", "DXMT_Y": "1", "HOME": "/h"]

    @Test func generalsOnlineTurnsOnWinesDotNetHost() {
        let e = Online.environment(for: .zeroHour, base: base, paths: GamePaths(profile: .zeroHour, root: URL(fileURLWithPath: "/r")))
        #expect(e["WINEDLLOVERRIDES"]?.contains("mscoree=b;mshtml=;") == true)
        #expect(e["DOTNET_PELoader_DisableMapping"] == "1")
    }

    @Test func cncnetUsesTheEngineOnlyAndItsOwnDotNet() {
        let e = Online.environment(for: .redAlert2, base: base, paths: GamePaths(profile: .redAlert2, root: URL(fileURLWithPath: "/r")))
        #expect(e["WINEDLLPATH"] == "/r/engine/lib/wine")
        #expect(e["WINEDLLOVERRIDES"] == "winemenubuilder.exe=;mshtml=;gameoverlayrenderer,gameoverlayrenderer64=")
        #expect(e["DOTNET_MULTILEVEL_LOOKUP"] == "0")
        #expect(e["DOTNET_X"] == nil && e["DXMT_Y"] == nil)
        #expect(e["HOME"] == "/h")
    }
}

@Suite struct GeneralsOnlineTests {
    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF43926)
    }

    @Test func upToDateNeedsNoPatch() throws {
        #expect(try GeneralsOnline.update(from: Data(#"{"result":0}"#.utf8)) == nil)
    }

    @Test func anUpdateMustComeFromTheOfficialCDNWithAKnownName() throws {
        let ok = try GeneralsOnline.update(from: Data(#"{"result":2,"patcher_name":"GeneralsOnline_update_100126_QFE1.exe","patcher_size":4096}"#.utf8))
        #expect(ok?.url.absoluteString == "https://cdn.playgenerals.online/GeneralsOnline_update_100126_QFE1.exe")
        #expect(throws: SetupError.self) {
            try GeneralsOnline.update(from: Data(#"{"result":2,"patcher_name":"../evil.exe","patcher_size":4096}"#.utf8))
        }
        #expect(throws: SetupError.self) {
            try GeneralsOnline.update(from: Data(#"{"result":2,"patcher_name":"GeneralsOnline_update_100126.exe","patcher_size":999999999999}"#.utf8))
        }
        #expect(throws: SetupError.self) { try GeneralsOnline.update(from: Data(#"{"result":7}"#.utf8)) }
    }

    @Test func versionCheckBodyCarriesTheClientCRC() {
        let body = GeneralsOnline.versionCheckBody(crc: 0xCBF43926)
        #expect(String(decoding: body, as: UTF8.self) == #"{"execrc":3421780262,"ver":1,"netver":1,"servicesver":1}"#)
    }
}

@Suite struct CnCNetTests {
    @Test func archiveEntriesMustStayInsideTheTarget() {
        #expect(CnCNet.isSafeEntry("package/Resources/clientogl.dll"))
        #expect(!CnCNet.isSafeEntry("/etc/passwd"))
        #expect(!CnCNet.isSafeEntry("package/../../x"))
    }

    @Test func thePackageNeverReplacesTheGameOrItsRenderer() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let package = dir.appendingPathComponent("package"), game = dir.appendingPathComponent("game"), backups = dir.appendingPathComponent("backups")
        for name in ["gamemd.exe", "ddraw.dll", "RA2MD.INI", "CnCNetYRLauncher.exe", "Resources/clientogl.dll"] { try write("new \(name)", to: package.appendingPathComponent(name)) }
        try write("old launcher", to: game.appendingPathComponent("CnCNetYRLauncher.exe"))
        try write("game exe", to: game.appendingPathComponent("gamemd.exe"))
        try CnCNet.merge(package: package, into: game, backups: backups)
        #expect(read(game.appendingPathComponent("gamemd.exe")) == "game exe")
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("ddraw.dll").path))
        #expect(!FileManager.default.fileExists(atPath: game.appendingPathComponent("RA2MD.INI").path))
        #expect(read(game.appendingPathComponent("Resources/clientogl.dll")) == "new Resources/clientogl.dll")
        #expect(read(game.appendingPathComponent("CnCNetYRLauncher.exe")) == "new CnCNetYRLauncher.exe")
        #expect(read(backups.appendingPathComponent("CnCNetYRLauncher.exe")) == "old launcher")
    }

    @Test func ourRendererIsRegisteredWithTheClient() {
        let ini = CnCNet.registerRenderer(in: "[Renderers]\nDDraw=DDRAW\n\n[DDRAW]\nUIName=DDraw\n")
        #expect(ini.contains("MacGames=MACGAMES_RA2"))
        #expect(ini.contains("[MACGAMES_RA2]\nUIName=MacGames (OpenGL)\nDLLName=macgames-ra2-ddraw.dll\nConfigFileName=ddraw.ini\nResConfigFileName=macgames-ra2-ddraw.ini"))
        #expect(CnCNet.registerRenderer(in: ini) == ini, "registering twice changes nothing")
    }
}
