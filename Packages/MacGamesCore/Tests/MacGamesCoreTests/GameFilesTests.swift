import Foundation
import Testing
@testable import MacGamesCore

@Suite struct GameFilesTests {
    struct Stage { let dir: URL; let paths: GamePaths; let runtime: RuntimeLayout; var user: URL }

    func stage(_ profile: GameProfile) throws -> Stage {
        let dir = try makeTempDir()
        let paths = GamePaths(profile: profile, root: dir.appendingPathComponent("root"))
        let runtime = RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: dir.appendingPathComponent("Helpers"))
        let user = paths.prefix.appendingPathComponent("drive_c/users/crossover")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: paths.prefix.appendingPathComponent("drive_c/users/Public"), withIntermediateDirectories: true)
        return Stage(dir: dir, paths: paths, runtime: runtime, user: user)
    }

    let context = LaunchContext(width: 2056, height: 1329)

    @Test func hogwartsTurnsOffTheDriverWarning() throws {
        let s = try stage(.hogwarts); defer { try? FileManager.default.removeItem(at: s.dir) }
        try GameFiles.prepare(.hogwarts, paths: s.paths, runtime: s.runtime, context: context)
        let ini = s.user.appendingPathComponent("AppData/Local/Hogwarts Legacy/Saved/Config/WindowsNoEditor/Engine.ini")
        #expect(read(ini) == "[SystemSettings]\nr.WarnOfBadDrivers=0\n")
        #expect(!FileManager.default.fileExists(atPath: s.paths.prefix.appendingPathComponent("drive_c/users/Public/AppData").path))
    }

    @Test func pathOfExileForcesDirectX12AndKeepsTheUsersWindowMode() throws {
        let s = try stage(.poe2); defer { try? FileManager.default.removeItem(at: s.dir) }
        let ini = s.user.appendingPathComponent("Documents/My Games/Path of Exile 2/poe2_production_Config.ini")
        try write("[DISPLAY]\nrenderer_type=Vulkan\nfullscreen=true\n", to: ini)
        try GameFiles.prepare(.poe2, paths: s.paths, runtime: s.runtime, context: context)
        let text = read(ini) ?? ""
        #expect(text.contains("renderer_type=DirectX12"))
        #expect(text.contains("fullscreen=true"))
        #expect(text.contains("borderless_windowed_fullscreen=true"))
        #expect(FileManager.default.fileExists(atPath: ini.path + ".macgames-backup"))
    }

    @Test func zeroHourGetsEdgeScrollingAndAClampedResolution() throws {
        let s = try stage(.zeroHour); defer { try? FileManager.default.removeItem(at: s.dir) }
        try GameFiles.prepare(.zeroHour, paths: s.paths, runtime: s.runtime, context: context)
        let text = read(s.user.appendingPathComponent("Documents/Command and Conquer Generals Zero Hour Data/Options.ini")) ?? ""
        #expect(text.hasPrefix("Resolution = 1920 1200\r\n"))
        #expect(text.contains("ScreenEdgeScrollEnabledInWindowedApp = yes\r\n"))
    }

    @Test func redAlertGetsItsRendererAndVideoKeys() throws {
        let s = try stage(.redAlert2); defer { try? FileManager.default.removeItem(at: s.dir) }
        let files = s.runtime.gameFiles("red-alert2")
        try write("ddraw", to: files.appendingPathComponent("ddraw.dll"))
        try write("[ddraw]\n", to: files.appendingPathComponent("ddraw.ini"))
        try write("shader", to: files.appendingPathComponent("Shaders/interpolation/catmull-rom-bilinear.glsl"))
        try write("[Video]\r\nScreenWidth=640\r\n", to: s.paths.installDir.appendingPathComponent("RA2.INI"))
        try GameFiles.prepare(.redAlert2, paths: s.paths, runtime: s.runtime, context: context)
        #expect(read(s.paths.installDir.appendingPathComponent("ddraw.dll")) == "ddraw")
        let ra2 = read(s.paths.installDir.appendingPathComponent("RA2.INI")) ?? ""
        #expect(ra2.contains("ScreenWidth=640\r\n"), "the user's width stays")
        #expect(ra2.contains("AllowHiResModes=yes\r\n"))
        #expect(read(s.paths.installDir.appendingPathComponent("RA2MD.INI"))?.contains("ScreenHeight=1200") == true)
    }

    @Test func witcherSwapsInTheProxyOnlyOverTheKnownLoader() throws {
        let s = try stage(.witcher3); defer { try? FileManager.default.removeItem(at: s.dir) }
        try write("proxy", to: s.runtime.gameFiles("witcher3").appendingPathComponent("amd_fidelityfx_loader_dx12.dll"))
        let loader = s.paths.installDir.appendingPathComponent("bin/x64_dx12/amd_fidelityfx_loader_dx12.dll")
        try write("original", to: loader)
        let warnings = try GameFiles.prepare(.witcher3, paths: s.paths, runtime: s.runtime, context: context)
        #expect(warnings.count == 1, "an unknown loader is skipped with a warning")
        #expect(read(loader) == "original")
        try GameFiles.prepare(.witcher3, paths: s.paths, runtime: s.runtime, context: context,
                              witcherSHA: sha256Hex(Data("original".utf8)))
        #expect(read(loader) == "proxy")
        #expect(read(loader.deletingLastPathComponent().appendingPathComponent("amd_fidelityfx_loader_dx12_orig.dll")) == "original")
        try GameFiles.prepare(.witcher3, paths: s.paths, runtime: s.runtime, context: context, witcherSHA: "x")
        #expect(read(loader) == "proxy", "already in place is fine")
    }

    @Test func heroesGetsItsWrapperSettingsAndSound() throws {
        let s = try stage(.heroes3); defer { try? FileManager.default.removeItem(at: s.dir) }
        let files = s.runtime.gameFiles("heroes3")
        try write("wrapper", to: files.appendingPathComponent("xdd.dll"))
        try write("[ddraw]\nrenderer=gdi\n", to: files.appendingPathComponent("ddraw.ini"))
        try write("stock", to: s.paths.installDir.appendingPathComponent("xdd.dll"))
        try Data(repeating: 0xCC, count: 0xe500).write(to: s.paths.installDir.appendingPathComponent("MSS32.DLL"))
        try GameFiles.prepare(.heroes3, paths: s.paths, runtime: s.runtime, context: context,
                              heroesSHA: sha256Hex(Data("stock".utf8)), heroesAudioSHAs: (nil, nil))
        #expect(read(s.paths.installDir.appendingPathComponent("xdd.dll")) == "wrapper")
        #expect(read(s.paths.installDir.appendingPathComponent("ddraw.ini")) == "[ddraw]\nrenderer=gdi\n")
        let mss = try Data(contentsOf: s.paths.installDir.appendingPathComponent("MSS32.DLL"))
        #expect(Array(mss[0xe39e..<0xe3d6]) == HeroesAudio.formatCode)
    }
}
