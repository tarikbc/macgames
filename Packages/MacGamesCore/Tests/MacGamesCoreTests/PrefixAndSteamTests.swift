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

    @Test func aoe4CopiesTheD3DMetalLibrariesIntoSystem32() {
        let p = GamePaths(profile: .aoe4, root: URL(fileURLWithPath: "/r"))
        let copies = PrefixSetup.graphicsCopies(for: p)
        #expect(copies.map(\.to.lastPathComponent) == ["dxgi.dll", "d3d11.dll", "d3d12.dll", "atidxx64.dll"])
        #expect(copies.allSatisfy { $0.from.path.hasPrefix("/r/deps/Frameworks/renderer/d3dmetal/wine/x86_64-windows/") })
        #expect(copies.allSatisfy { $0.to.path.hasPrefix("/r/prefix/drive_c/windows/system32/") })
    }

    @Test func cs2CopiesWinemetalForBothArchitectures() {
        let p = GamePaths(profile: .cs2, root: URL(fileURLWithPath: "/r"))
        let copies = PrefixSetup.graphicsCopies(for: p)
        #expect(copies.map(\.from.path) == ["/r/engine/lib/wine/x86_64-windows/winemetal.dll", "/r/engine/lib/wine/i386-windows/winemetal.dll"])
        #expect(copies.map(\.to.path) == ["/r/prefix/drive_c/windows/system32/winemetal.dll", "/r/prefix/drive_c/windows/syswow64/winemetal.dll"])
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
        let a = ["HOME": "/a", "TERM": "x", "WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        let b = ["HOME": "/b", "WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        #expect(SteamLaunch.fingerprint(a) == SteamLaunch.fingerprint(b))
    }

    @Test func fingerprintChangesWithManagedKeys() {
        let a = ["WINEPREFIX": "/p", "MTL_HUD_ENABLED": "0"]
        let b = ["WINEPREFIX": "/p", "MTL_HUD_ENABLED": "1"]
        #expect(SteamLaunch.fingerprint(a) != SteamLaunch.fingerprint(b))
    }
}
