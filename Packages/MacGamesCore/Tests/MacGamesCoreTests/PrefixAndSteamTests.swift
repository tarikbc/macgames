import Foundation
import Testing
@testable import MacGamesCore

@Suite struct PrefixSetupTests {
    @Test func userFolderLinksBecomeEmptyRealFolders() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let prefix = dir.appendingPathComponent("prefix")
        let user = prefix.appendingPathComponent("drive_c/users/crossover")
        try FileManager.default.createDirectory(at: user.appendingPathComponent("AppData"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: user.appendingPathComponent("Documents").path, withDestinationPath: dir.path)
        try PrefixSetup.replaceUserLinks(prefix: prefix)
        let docs = user.appendingPathComponent("Documents")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: docs.path)) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: docs.path).isEmpty)
        #expect(FileManager.default.fileExists(atPath: user.appendingPathComponent("AppData").path))
    }

    func targets(_ profile: GameProfile) -> [String] {
        PrefixSetup.graphicsCopies(for: GamePaths(profile: profile, root: URL(fileURLWithPath: "/r")))
            .map { "\($0.to.deletingLastPathComponent().lastPathComponent)/\($0.to.lastPathComponent)" }
    }

    @Test func sharedSteamGetsD3DMetalAndTheDXMTBridge() {
        #expect(targets(.aoe4) == ["system32/dxgi.dll", "system32/d3d11.dll", "system32/d3d12.dll", "system32/atidxx64.dll",
                                   "system32/winemetal.dll", "syswow64/winemetal.dll"])
        let copies = PrefixSetup.graphicsCopies(for: GamePaths(profile: .cs2, root: URL(fileURLWithPath: "/r")))
        #expect(copies[0].from.path == "/r/deps/Frameworks/renderer/d3dmetal/wine/x86_64-windows/dxgi.dll")
        #expect(copies[4].from.path == "/r/engine/lib/wine/x86_64-windows/winemetal.dll")
    }

    @Test func skyrimGetsTheEnginesDXMTInBothSystemFolders() {
        #expect(targets(.skyrim).count == 8)
        #expect(targets(.skyrim).contains("syswow64/d3d10core.dll"))
    }

    @Test func battleNetAddsThe32BitDXMTClientRenderer() {
        #expect(targets(.diablo2Resurrected) == ["system32/dxgi.dll", "system32/d3d11.dll", "system32/d3d12.dll", "system32/atidxx64.dll",
                                                 "syswow64/dxgi.dll", "syswow64/d3d11.dll", "syswow64/d3d10core.dll", "syswow64/winemetal.dll"])
    }

    @Test func rockstarReplacesD3D11AndDXGIWithWineD3D() {
        let copies = PrefixSetup.graphicsCopies(for: GamePaths(profile: .rdr2, root: URL(fileURLWithPath: "/r")))
        let source = Dictionary(uniqueKeysWithValues: copies.map { ($0.to.lastPathComponent, $0.from.path) })
        #expect(source["d3d11.dll"] == "/r/packs/rockstar/RockstarRenderer/d3d11.dll")
        #expect(source["dxgi.dll"] == "/r/packs/rockstar/RockstarRenderer/dxgi.dll")
        #expect(source["d3d12.dll"] == "/r/deps/Frameworks/renderer/d3dmetal/wine/x86_64-windows/d3d12.dll")
    }

    @Test func gtaVTakesD3DMetalFromApplesPack() {
        let copies = PrefixSetup.graphicsCopies(for: GamePaths(profile: .gta5, root: URL(fileURLWithPath: "/r")))
        let source = Dictionary(uniqueKeysWithValues: copies.map { ($0.to.lastPathComponent, $0.from.path) })
        #expect(source["d3d12.dll"] == "/r/packs/apple-d3dmetal-4.0b2/wine/x86_64-windows/d3d12.dll")
        #expect(source["atidxx64.dll"] == "/r/deps/Frameworks/renderer/d3dmetal/wine/x86_64-windows/atidxx64.dll")
    }

    @Test func rootDrivesPointAtTheEnvironment() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = GamePaths(profile: .rdr2, root: dir)
        let devices = p.prefix.appendingPathComponent("dosdevices")
        try FileManager.default.createDirectory(at: devices, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: devices.appendingPathComponent("z:").path, withDestinationPath: "/")
        try PrefixSetup.mapRootDrives(paths: p)
        for letter in ["y", "z"] {
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: devices.appendingPathComponent("\(letter):").path) == dir.path)
        }
    }

    @Test func applyingCopiesReplacesExistingFiles() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let from = dir.appendingPathComponent("a.dll"), to = dir.appendingPathComponent("sys/a.dll")
        try write("new", to: from); try write("old", to: to)
        try PrefixSetup.apply([.init(from: from, to: to)])
        #expect(read(to) == "new")
    }

    @Test func wineBusEnablesSDLControllers() {
        let commands = PrefixSetup.wineBusCommands
        #expect(commands.count == 3)
        #expect(commands.map { $0[4] } == ["Enable SDL", "DisableHidraw", "Map Controllers"])
        #expect(commands.allSatisfy { $0.prefix(2) == ["reg", "add"] && $0.contains("HKLM\\System\\CurrentControlSet\\Services\\WineBus") && $0.suffix(5) == ["/t", "REG_DWORD", "/d", "1", "/f"] })
    }
}

@Suite struct SteamLaunchTests {
    let paths = GamePaths(profile: .aoe4, root: URL(fileURLWithPath: "/r"))

    @Test func openPassesOnlyTheCEFFlag() {
        #expect(SteamLaunch.arguments(paths, .open) == [paths.steamExe.path, "-cef-disable-gpu"])
    }

    @Test func installUsesTheSteamURL() {
        #expect(SteamLaunch.arguments(paths, .install) == [paths.steamExe.path, "-cef-disable-gpu", "steam://install/1466860"])
    }

    @Test func playUsesApplaunchWithExtraGameArguments() {
        #expect(SteamLaunch.arguments(paths, .play(["-x"])) == [paths.steamExe.path, "-cef-disable-gpu", "-applaunch", "1466860", "-x"])
    }

    @Test func cs2DisplayArgumentsUseTheScreenSizeInPoints() {
        #expect(SteamLaunch.cs2DisplayArguments(width: 1728, height: 1117) == ["-windowed", "-noborder", "-w", "1728", "-h", "1117"])
    }

    @Test func fingerprintIgnoresUnmanagedKeys() {
        let a = ["PWD": "/a", "TERM": "x", "WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        let b = ["PWD": "/b", "WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        #expect(SteamLaunch.fingerprint(a) == SteamLaunch.fingerprint(b))
    }

    @Test func fingerprintChangesWithManagedKeys() {
        let a = ["WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        let b = ["WINEPREFIX": "/p", "MTL_HUD_ENABLED": "1"]
        #expect(SteamLaunch.fingerprint(a) != SteamLaunch.fingerprint(b))
    }
}
