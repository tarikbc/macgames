import Foundation
import Testing
@testable import MacGamesCore

/// Overwatch runs on its own engine pack, built from Recall's Wine and DXMT, and starts through Battle.net.
@Suite struct OverwatchSetupTests {
    let paths = GamePaths(profile: .overwatch, root: URL(fileURLWithPath: "/r"))

    func env(_ profile: GameProfile = .overwatch, hud: Bool = false) -> [String: String] {
        WineEnvironment.make(profile: profile, paths: GamePaths(profile: profile, root: URL(fileURLWithPath: "/r")),
                             inherited: ["HOME": "/Users/me", "PATH": "/usr/bin:/bin"], optimized: false, hud: hud,
                             bridge: URL(fileURLWithPath: "/b"))
    }

    @Test func overwatchHasItsOwnEngineAndNoTemplate() {
        let environment = GameEnvironment.overwatch
        #expect(environment.enginePack == "overwatch-recall")
        #expect(environment.packs == ["overwatch-recall"])
        #expect(!environment.usesTemplate)
        #expect(environment.engineOverlays.isEmpty)
        #expect(environment.prefixDLLs.isEmpty)
        #expect(!environment.sdlControllers)
        #expect(GameEnvironment.steam.usesTemplate)
    }

    @Test func overwatchInstallsAndStartsThroughBattleNet() {
        #expect(GameEnvironment.overwatch.launcher == .battleNet)
        #expect(GameProfile.overwatch.launch == .battleNet)
        #expect(GameProfile.overwatch.battleNetProduct == "Pro")
        #expect(GameProfile.diablo4BattleNet.battleNetProduct == nil)
        #expect(paths.gameExe.path == "/r/prefix/drive_c/Program Files (x86)/Overwatch/_retail_/Overwatch.exe")
        #expect(GameProfile.overwatch.executableName == "Overwatch.exe")
    }

    @Test func theEnginePackComesFromTheSecondPackRelease() {
        #expect(Packs.download("overwatch-recall").url.absoluteString
            == "https://github.com/tarikbc/macgames/releases/download/packs-2/macgames-pack-overwatch-recall.tar.xz")
        #expect(Packs.download("skyrim").url.absoluteString
            == "https://github.com/tarikbc/macgames/releases/download/packs-1/macgames-pack-skyrim.tar.xz")
        #expect(Packs.pinned["overwatch"] == nil, "the old Overwatch overlay pack is no longer used")
    }

    @Test func overwatchGetsRecallsEnvironment() {
        let e = env()
        let expected = [
            "WINEMSYNC": "1", "WINEESYNC": "0", "ROSETTA_ADVERTISE_AVX": "1", "WINE_SIMULATE_WRITECOPY": "1",
            "CX_ACTIVE_GRAPHICS_BACKEND": "dxmt", "CX_GRAPHICS_BACKEND": "dxmt",
            "DXMT_CANVAS_DRAWABLES": "3", "DXMT_CANVAS_OVERLAY": "0", "DXMT_USE_DEFAULT_METAL_CACHE": "1",
            "DXMT_PIPELINE_CACHE_NAMESPACE": "ow2-source-v1", "DXMT_PIPELINE_CACHE_PREWARM_MS": "10000",
            "DXMT_PIPELINE_CACHE_PREWARM_LIMIT": "128", "DXMT_PIPELINE_CACHE_PREFER_EXPENSIVE": "1",
            "WINEMAC_MOUSELOOK": "Overwatch.exe", "WINE_GAME_MODE": "Overwatch.exe", "DXMT_PREPARE_SHADERS": "1",
            "WINEARCH": "win64", "DXMT_LOG_LEVEL": "error", "DXMT_LOG_PATH": "none", "QT_SCALE_FACTOR": "2",
            "CX_APPLEGPTK_LIBD3DSHARED_PATH": "/r/engine/lib/external/libd3dshared.dylib",
            "DXMT_SHADER_CACHE_PATH": "/r/games/overwatch/cache/shaders",
            "DXMT_PIPELINE_CACHE_PATH": "/r/games/overwatch/cache/pipelines",
            "DXMT_CONFIG_FILE": #"Z:\r\games\overwatch\dxmt.conf"#,
            "HOME": "/r/games/overwatch/home",
        ]
        for (key, value) in expected { #expect(e[key] == value, "\(key)") }
        #expect(e["WINEDLLOVERRIDES"] == WineEnvironment.baseOverrides + "d3d11,dxgi,d3d10core,winemetal=b;d3d12=")
        #expect(e["TMPDIR"]?.hasPrefix("/r/games/overwatch/tmp") == true)
    }

    @Test func aSelfContainedEngineGetsNoTemplateLibraryPaths() {
        let e = env()
        #expect(e["DYLD_FALLBACK_LIBRARY_PATH"] == nil)
        #expect(e["GST_PLUGIN_PATH"] == nil)
        #expect(e["GST_REGISTRY"] == nil)
        #expect(e["AOELAB_STEAM_SINGLEPROCESS"] == nil)
        #expect(env(.cs2)["DYLD_FALLBACK_LIBRARY_PATH"]?.hasPrefix("/r/deps/Frameworks:") == true)
    }

    @Test func overwatchTurnsOnRetinaModeForTheWholePrefix() {
        #expect(GameRecipes.registry(for: .overwatch)
            == [RegistryValue(key: #"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#, name: "RetinaMode", value: .string("Y"))])
    }

    @Test func battleNetStartsWithTheFlagsOfItsEnvironment() {
        #expect(GameRecipes.battleNetFlags(for: .overwatch) == [
            "--disable-gpu-compositing", "--from-launcher", "--in-process-gpu", "--use-gl=angle",
            "--use-angle=swiftshader", "--force-device-scale-factor=2"])
        #expect(GameRecipes.battleNetFlags(for: .battlenet) == ["--in-process-gpu", "--use-gl=angle", "--use-angle=d3d11"])
    }
}

/// An engine pack replaces the app's engine, overlays and dependency links with one self-contained engine.
@Suite struct EnginePackInstallTests {
    func fixture() throws -> (dir: URL, runtime: RuntimeLayout, paths: GamePaths) {
        let dir = try makeTempDir("enginepack")
        let res = dir.appendingPathComponent("Runtime")
        try write("app wine", to: res.appendingPathComponent("Engine/bin/wine"))
        try write(#"{"lib/libfreetype.6.dylib": "libfreetype.6.dylib"}"#, to: res.appendingPathComponent("dependency-links.json"))
        try write("v1", to: res.appendingPathComponent("VERSION"))
        let runtime = RuntimeLayout(resources: res, helpers: dir.appendingPathComponent("Helpers"))
        let paths = GamePaths(profile: .overwatch, root: dir.appendingPathComponent("root"))
        let engine = paths.pack("overwatch-recall").appendingPathComponent("Engine")
        try write("recall wine", to: engine.appendingPathComponent("bin/wine"))
        try write("recall freetype", to: engine.appendingPathComponent("lib/libfreetype.6.dylib"))
        try write("pin-1", to: paths.pack("overwatch-recall").appendingPathComponent(".macgames-pack"))
        return (dir, runtime, paths)
    }

    @Test func theEngineIsAByteCopyOfThePackEngine() throws {
        let (dir, runtime, paths) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try EngineInstaller(runtime: runtime).install(for: paths)
        #expect(read(paths.engine.appendingPathComponent("bin/wine")) == "recall wine")
        #expect(read(paths.engine.appendingPathComponent("lib/libfreetype.6.dylib")) == "recall freetype")
        let link = paths.engine.appendingPathComponent("lib/libfreetype.6.dylib").path
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link)) == nil, "no links into a template")
    }

    @Test func aNewAppRuntimeKeepsThePackEngine() throws {
        let (dir, runtime, paths) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try EngineInstaller(runtime: runtime).install(for: paths)
        try write("v2", to: runtime.resources.appendingPathComponent("VERSION"))
        #expect(try EngineInstaller(runtime: runtime).install(for: paths) == false)
    }

    @Test func aNewPackReplacesTheEngine() throws {
        let (dir, runtime, paths) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try EngineInstaller(runtime: runtime).install(for: paths)
        try write("recall wine 2", to: paths.pack("overwatch-recall").appendingPathComponent("Engine/bin/wine"))
        try write("pin-2", to: paths.pack("overwatch-recall").appendingPathComponent(".macgames-pack"))
        #expect(try EngineInstaller(runtime: runtime).install(for: paths) == true)
        #expect(read(paths.engine.appendingPathComponent("bin/wine")) == "recall wine 2")
    }

    @Test func aPackWithoutAnEngineFails() throws {
        let (dir, runtime, paths) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.removeItem(at: paths.pack("overwatch-recall").appendingPathComponent("Engine"))
        #expect(throws: SetupError.self) { try EngineInstaller(runtime: runtime).install(for: paths) }
        #expect(!FileManager.default.fileExists(atPath: paths.engine.path))
    }
}

@Suite(.serialized) struct EnginePackSetupTests {
    @Test func anEnginePackEnvironmentNeedsNoTemplate() throws {
        let env = try FakeEnvironment(.overwatch); defer { env.cleanUp() }
        // The download cache has no template, so a download attempt would fail.
        try env.runtime.ensureTemplate()
        #expect(!FileManager.default.fileExists(atPath: env.runtime.paths.frameworks.path))
    }
}
