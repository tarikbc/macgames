import Foundation
import Testing
@testable import MacGamesCore

@Suite struct RecipeEnvironmentTests {
    let bridge = URL(fileURLWithPath: "/b")
    func env(_ profile: GameProfile, root: String = "/r") -> [String: String] {
        WineEnvironment.make(profile: profile, paths: GamePaths(profile: profile, root: URL(fileURLWithPath: root)),
                             inherited: ["HOME": "/Users/me"], optimized: false, hud: false, bridge: bridge)
    }

    @Test func heroesUsesBuiltinsAndItsDirectDrawWrapper() {
        let e = env(.heroes3)
        #expect(e["WINEDLLPATH"] == "/r/engine/lib/wine")
        #expect(e["WINEDLLOVERRIDES"]?.hasSuffix("dxgi,d3d10,d3d10_1,d3d10core,d3d11,d3d9,ddraw=b;xdd=n") == true)
        #expect(e["SteamAppId"] == "4921760")
        #expect(e["HOME"] == "/r/games/heroes3/home")
    }

    @Test func battleNetTurnsOffMsyncAndSingleProcessSteam() {
        let e = env(.diablo4BattleNet)
        #expect(e["WINEMSYNC"] == "0")
        #expect(e["AOELAB_STEAM_SINGLEPROCESS"] == nil)
        #expect(e["WINE_LARGE_ADDRESS_AWARE"] == "1")
        #expect(e["QT_OPENGL"] == "software")
    }

    @Test func gtaVUsesApplesPinnedD3DMetal() {
        let e = env(.gta5)
        #expect(e["WINEDLLPATH"] == "/r/packs/apple-d3dmetal-4.0b2/wine:/r/engine/lib/wine")
        #expect(e["CX_APPLEGPTK_LIBD3DSHARED_PATH"] == "/r/packs/apple-d3dmetal-4.0b2/external/libd3dshared.dylib")
        #expect(e["WINEDLLOVERRIDES"] == "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;nvapi64,nvngx=")
        #expect(e["GTM_ROCKSTAR_SWIFTSHADER"] == "1")
    }

    @Test func witcherLoadsItsFidelityFXProxy() {
        #expect(env(.witcher3)["WINEDLLOVERRIDES"]?.hasSuffix(";amd_fidelityfx_loader_dx12=n") == true)
        #expect(env(.witcher3)["CFFIXED_USER_HOME"] == "/r/games/witcher3/home")
    }

    @Test func eldenRingCarriesItsAppIDForADirectStart() {
        let e = env(.eldenRing)
        #expect(e["SteamAppId"] == "1245620")
        #expect(e["SteamGameId"] == nil)
    }

    @Test func skyrimAndOverwatchUseTheirOwnDXMTOverrides() {
        #expect(env(.skyrim)["WINEDLLOVERRIDES"]?.contains("xaudio2_6,xaudio2_7,x3daudio1_6,x3daudio1_7=n,b") == true)
        #expect(env(.overwatch)["WINEDLLOVERRIDES"]?.contains("d3d12,d3d12core=;") == true)
        #expect(env(.overwatch)["DXMT_OWT_RECIPE_DIR"] == "/r/games/overwatch/graphics/recipes")
    }

    @Test func sandboxFoldersMatchTheEnvironment() {
        let p = GamePaths(profile: .poe2, root: URL(fileURLWithPath: "/r"))
        #expect(GameRecipes.sandboxFolders(for: .poe2, paths: p).map(\.lastPathComponent) == ["cache", "config", "share", "tmp"])
        #expect(GameRecipes.sandboxFolders(for: .aoe4, paths: p).isEmpty)
    }
}

@Suite struct EnvironmentPathTests {
    @Test func battleNetGamesInstallUnderProgramFiles() {
        let p = GamePaths(profile: .diablo2Resurrected, root: URL(fileURLWithPath: "/r"))
        #expect(p.gameExe.path == "/r/prefix/drive_c/Program Files (x86)/Diablo II Resurrected/D2R.exe")
        #expect(p.battleNetExe.path == "/r/prefix/drive_c/Program Files (x86)/Battle.net/Battle.net.exe")
    }

    @Test func eachEnvironmentHasItsOwnRoot() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(GamePaths.defaultRoot(for: .rockstar, home: home).path == "/Users/x/Library/Application Support/macgames/rockstar")
        #expect(GamePaths.defaultRoot(home: home).path == "/Users/x/Library/Application Support/macgames/steam")
    }

    @Test func windowsPathsUseDriveC() {
        let p = GamePaths(profile: .eldenRing, root: URL(fileURLWithPath: "/r"))
        #expect(p.windowsPath(p.gameExe) == "C:\\Program Files (x86)\\Steam\\steamapps\\common\\ELDEN RING\\Game\\eldenring.exe")
    }
}

@Suite struct PackInstallTests {
    @Test func aPackUnpacksIntoItsFolderOnce() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = GamePaths(profile: .skyrim, root: dir.appendingPathComponent("skyrim"))
        // Build a tiny pack archive the way the release does.
        let src = dir.appendingPathComponent("src/skyrim")
        try write("dxmt", to: src.appendingPathComponent("Overlays/skyrim/lib/wine/x86_64-windows/d3d11.dll"))
        let cache = dir.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let runner = ProcessRunner(logDirectory: dir.appendingPathComponent("logs"))
        try runner.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-cJf", cache.appendingPathComponent("macgames-pack-skyrim.tar.xz").path,
                                                            "-C", dir.appendingPathComponent("src").path, "skyrim"])
        try Packs.install("skyrim", paths: p, downloader: Downloader(cache: cache), runner: runner)
        #expect(read(p.pack("skyrim").appendingPathComponent("Overlays/skyrim/lib/wine/x86_64-windows/d3d11.dll")) == "dxmt")
        try write("touched", to: p.pack("skyrim").appendingPathComponent("Overlays/skyrim/lib/wine/x86_64-windows/d3d11.dll"))
        try Packs.install("skyrim", paths: p, downloader: Downloader(cache: cache), runner: runner)
        #expect(read(p.pack("skyrim").appendingPathComponent("Overlays/skyrim/lib/wine/x86_64-windows/d3d11.dll")) == "touched", "kept, not unpacked again")
    }
}
