import Foundation
import Testing
@testable import MacGamesCore

@Suite struct WineEnvironmentTests {
    let root = URL(fileURLWithPath: "/tmp/mg/aoe4")
    let bridge = URL(fileURLWithPath: "/Apps/MacGames.app/Contents/Helpers/MacGamesBridge")

    func paths(_ profile: GameProfile) -> GamePaths { GamePaths(profile: profile, root: root) }

    @Test func stripsInheritedWineAndLoaderKeys() {
        let inherited = ["HOME": "/Users/me", "WINEPREFIX": "/old", "DYLD_INSERT_LIBRARIES": "x", "AOELAB_SOFTFAULT_GAME": "1",
                         "X87_ALWAYS_NONE": "1", "SDL_FOO": "1", "MACGAMES_OPTIMIZED_SHA256": "old", "PATH": "/usr/bin"]
        let env = WineEnvironment.make(profile: .cs2, paths: paths(.cs2), inherited: inherited, optimized: false, hud: false, bridge: bridge)
        #expect(env["HOME"] == "/Users/me")
        #expect(env["PATH"] == "/usr/bin")
        #expect(env["DYLD_INSERT_LIBRARIES"] == nil)
        #expect(env["AOELAB_SOFTFAULT_GAME"] == nil)
        #expect(env["X87_ALWAYS_NONE"] == nil)
        #expect(env["SDL_FOO"] == nil)
        #expect(env["MACGAMES_OPTIMIZED_SHA256"] == nil)
        #expect(env["WINEPREFIX"] == "/tmp/mg/aoe4/prefix")
    }

    @Test func setsCommonWineValues() {
        let env = WineEnvironment.make(profile: .aoe4, paths: paths(.aoe4), inherited: [:], optimized: false, hud: true, bridge: bridge)
        #expect(env["WINELOADER"] == "/tmp/mg/aoe4/engine/bin/wine")
        #expect(env["WINESERVER"] == "/tmp/mg/aoe4/engine/bin/wineserver")
        #expect(env["WINEDEBUG"] == "-all")
        #expect(env["WINEMSYNC"] == "1")
        #expect(env["WINEESYNC"] == "0")
        #expect(env["ROSETTA_ADVERTISE_AVX"] == "1")
        #expect(env["MTL_HUD_ENABLED"] == "1")
        #expect(env["AOELAB_STEAM_SINGLEPROCESS"] == "1")
        #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == "/tmp/mg/aoe4/deps/Frameworks:/tmp/mg/aoe4/deps/Frameworks/GStreamer.framework/Versions/1.0/lib:/usr/lib")
        #expect(env["GST_REGISTRY"] == "/tmp/mg/aoe4/gstreamer-registry.bin")
        #expect(env["SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"] == "1")
    }

    @Test func aoe4UsesD3DMetal() {
        let env = WineEnvironment.make(profile: .aoe4, paths: paths(.aoe4), inherited: [:], optimized: false, hud: false, bridge: bridge)
        #expect(env["WINEDLLPATH"] == "/tmp/mg/aoe4/deps/Frameworks/renderer/d3dmetal/wine:/tmp/mg/aoe4/engine/lib/wine")
        #expect(env["WINEDLLOVERRIDES"] == "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;dxgi,d3d11,d3d12,atidxx64=n,b;nvapi64,nvngx=")
        #expect(env["MTL_HUD_ENABLED"] == "0")
    }

    @Test func aoe4OptimizedSetsAllSidecarKeysTogether() {
        let env = WineEnvironment.make(profile: .aoe4, paths: paths(.aoe4), inherited: [:], optimized: true, hud: false, bridge: bridge)
        #expect(env["AOELAB_SOFTFAULT_GAME"] == "1")
        #expect(env["AOELAB_CODE_CACHE_GAME"] == "1")
        #expect(env["AOELAB_SIDECAR_PATH"] == bridge.path)
        #expect(env["MACGAMES_OPTIMIZED_SHA256"] == "5380c577805565817f528af6eac385263413fa6815553f9a31fa62561cb45e8c")
    }

    @Test func aoe4UnoptimizedSetsNoSidecarKeys() {
        let env = WineEnvironment.make(profile: .aoe4, paths: paths(.aoe4), inherited: [:], optimized: false, hud: false, bridge: bridge)
        for key in ["AOELAB_SOFTFAULT_GAME", "AOELAB_CODE_CACHE_GAME", "AOELAB_SIDECAR_PATH", "MACGAMES_OPTIMIZED_SHA256"] {
            #expect(env[key] == nil, "\(key) must be unset")
        }
    }

    @Test func cs2UsesDXMTAndNeverTheSidecar() {
        let p = GamePaths(profile: .cs2, root: URL(fileURLWithPath: "/tmp/mg/cs2"))
        let env = WineEnvironment.make(profile: .cs2, paths: p, inherited: [:], optimized: true, hud: false, bridge: bridge)
        #expect(env["WINEDLLPATH"] == "/tmp/mg/cs2/engine/lib/wine")
        #expect(env["WINEDLLOVERRIDES"] == "winemenubuilder.exe=;mscoree,mshtml=;gameoverlayrenderer,gameoverlayrenderer64=;dxgi,d3d11,d3d10core,winemetal=b;nvapi64,nvngx=")
        #expect(env["DXMT_CS2_EARLY_COMPILE"] == "1")
        #expect(env["DXMT_SHADER_CACHE_PATH"] == "/tmp/mg/cs2/graphics/shader-cache")
        #expect(env["DXMT_CS2_PIPELINE_CACHE"] == "/tmp/mg/cs2/graphics/game-archives")
        #expect(env["DXMT_CS2_RECIPE_DIR"] == "/tmp/mg/cs2/graphics/recipes")
        #expect(env["DXMT_LOG_PATH"] == "/tmp/mg/cs2/logs")
        #expect(env["AOELAB_SOFTFAULT_GAME"] == nil)
        #expect(env["AOELAB_SIDECAR_PATH"] == nil)
    }
}

@Suite struct GamePathsTests {
    @Test func aoe4Layout() {
        let p = GamePaths(profile: .aoe4, root: URL(fileURLWithPath: "/r"))
        #expect(p.engine.path == "/r/engine")
        #expect(p.frameworks.path == "/r/deps/Frameworks")
        #expect(p.steamExe.path == "/r/prefix/drive_c/Program Files (x86)/Steam/steam.exe")
        #expect(p.gameExe.path == "/r/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Age of Empires IV/RelicCardinal.exe")
        #expect(p.appManifest.path == "/r/prefix/drive_c/Program Files (x86)/Steam/steamapps/appmanifest_1466860.acf")
    }

    @Test func cs2ExecutableIsUnderGameBin() {
        let p = GamePaths(profile: .cs2, root: URL(fileURLWithPath: "/r"))
        #expect(p.gameExe.path == "/r/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Counter-Strike Global Offensive/game/bin/win64/cs2.exe")
    }

    @Test func defaultRootIsShortAndPerGame() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let root = GamePaths.defaultRoot(for: .cs2, home: home)
        #expect(root.path == "/Users/someone/Library/Application Support/macgames/cs2")
    }

    @Test func profilesAreLookedUpById() {
        #expect(GameProfile.named("aoe4") == .aoe4)
        #expect(GameProfile.named("cs2") == .cs2)
        #expect(GameProfile.named("doom") == nil)
        #expect(GameProfile.cs2.engineOverlays == ["cs2", "controllers"])
        #expect(GameProfile.aoe4.engineOverlays == ["controllers"])
    }
}
