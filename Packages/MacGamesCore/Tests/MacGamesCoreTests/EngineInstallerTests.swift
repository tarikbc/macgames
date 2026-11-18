import Foundation
import Testing
@testable import MacGamesCore

@Suite struct EngineInstallerTests {
    /// A tiny stand-in for the vendored runtime.
    func fakeRuntime(in dir: URL, version: String = "v1") throws -> RuntimeLayout {
        let res = dir.appendingPathComponent("Runtime")
        try write("base wine", to: res.appendingPathComponent("Engine/bin/wine"))
        try write("base d3d11", to: res.appendingPathComponent("Engine/lib/wine/i386-windows/d3d11.dll"))
        try write("base winebus", to: res.appendingPathComponent("Engine/lib/wine/x86_64-unix/winebus.so"))
        try write("cs2 d3d11 32", to: res.appendingPathComponent("Overlays/cs2/lib/wine/i386-windows/d3d11.dll"))
        try write("cs2 d3d11 64", to: res.appendingPathComponent("Overlays/cs2/lib/wine/x86_64-windows/d3d11.dll"))
        try write("controller winebus", to: res.appendingPathComponent("Overlays/controllers/lib/wine/x86_64-unix/winebus.so"))
        try write("fixed ntdll", to: res.appendingPathComponent("Overlays/ntdllfix/lib/wine/x86_64-unix/ntdll.so"))
        try write("notch winemac", to: res.appendingPathComponent("Overlays/aomretold/lib/wine/x86_64-unix/winemac.so"))
        try write("skyrim d3d11 64", to: res.appendingPathComponent("Overlays/skyrim/lib/wine/x86_64-windows/d3d11.dll"))
        try write("cef kernelbase", to: res.appendingPathComponent("Overlays/rockstar/lib/wine/x86_64-windows/kernelbase.dll"))
        try write("""
        {"lib/libfreetype.6.dylib": "libfreetype.6.dylib",
         "lib/wine/x86_64-unix/d3d11.so": "renderer/d3dmetal/external/libd3dshared.dylib",
         "lib/wine/x86_64-windows/d3d11.dll": "renderer/d3dmetal/wine/x86_64-windows/d3d11.dll",
         "lib/wine/x86_64-windows/d3d12.dll": "renderer/d3dmetal/wine/x86_64-windows/d3d12.dll"}
        """, to: res.appendingPathComponent("dependency-links.json"))
        try write(version, to: res.appendingPathComponent("VERSION"))
        return RuntimeLayout(resources: res, helpers: dir.appendingPathComponent("Helpers"))
    }

    @Test func copiesBaseThenOverlaysInOrder() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runtime = try fakeRuntime(in: dir)
        let paths = GamePaths(profile: .cs2, root: dir.appendingPathComponent("cs2"))
        try EngineInstaller(runtime: runtime).install(for: paths)
        #expect(read(paths.wine) == "base wine")
        #expect(read(paths.engine.appendingPathComponent("lib/wine/i386-windows/d3d11.dll")) == "cs2 d3d11 32")
        #expect(read(paths.engine.appendingPathComponent("lib/wine/x86_64-unix/winebus.so")) == "controller winebus")
    }

    @Test func linksDependenciesAbsolutelyIntoFrameworks() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("aoe4"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: paths.engine.appendingPathComponent("lib/libfreetype.6.dylib").path)
                == paths.frameworks.appendingPathComponent("libfreetype.6.dylib").path)
    }

    @Test func sharedEngineCarriesEveryGamesOverlays() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("steam"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        #expect(read(paths.dxmtDLLs.appendingPathComponent("x86_64-windows/d3d11.dll")) == "cs2 d3d11 64")
        #expect(read(paths.engineDLLs.appendingPathComponent("x86_64-unix/winebus.so")) == "controller winebus")
        #expect(read(paths.engineDLLs.appendingPathComponent("x86_64-unix/ntdll.so")) == "fixed ntdll")
        #expect(GameEnvironment.steam.engineOverlays == ["ntdllfix", "cs2", "aomretold", "controllers"])
    }

    /// Wine searches lib/wine before WINEDLLPATH, so a DLL there reaches every game of the environment.
    @Test func mixedEngineKeepsBothRenderersOutOfLibWine() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("steam"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        let fm = FileManager.default
        for name in ["d3d11.dll", "d3d12.dll"] {
            let dll = paths.engineDLLs.appendingPathComponent("x86_64-windows/\(name)")
            #expect(!fm.fileExists(atPath: dll.path) && (try? fm.destinationOfSymbolicLink(atPath: dll.path)) == nil, "\(name)")
        }
        // DXMT's 32-bit DLLs have no D3DMetal counterpart and stay with the engine.
        #expect(read(paths.engineDLLs.appendingPathComponent("i386-windows/d3d11.dll")) == "cs2 d3d11 32")
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.engineDLLs.appendingPathComponent("x86_64-unix/d3d11.so").path)
                == paths.frameworks.appendingPathComponent("renderer/d3dmetal/external/libd3dshared.dylib").path)
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.engine.appendingPathComponent("lib/libfreetype.6.dylib").path)
                == paths.frameworks.appendingPathComponent("libfreetype.6.dylib").path)
    }

    @Test func singleRendererEngineKeepsD3DMetalInLibWine() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .rdr2, root: dir.appendingPathComponent("rockstar"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: paths.engineDLLs.appendingPathComponent("x86_64-windows/d3d11.dll").path)
                == paths.frameworks.appendingPathComponent("renderer/d3dmetal/wine/x86_64-windows/d3d11.dll").path)
        #expect(!FileManager.default.fileExists(atPath: paths.dxmtDLLs.path))
    }

    @Test func overlayFilesWinOverDependencyLinks() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .skyrim, root: dir.appendingPathComponent("skyrim"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        let dll = paths.engineDLLs.appendingPathComponent("x86_64-windows/d3d11.dll")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: dll.path)) == nil)
        #expect(read(dll) == "skyrim d3d11 64")
    }

    /// D3DMetal's Windows DLLs and its libd3dshared must be one version: an older libd3dshared
    /// writes into a newer dxgi.dll's code, and Steam's web helper crashes (issue #18).
    @Test func ownD3DMetalTakesItsLinksFromItsPack() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .gta5, root: dir.appendingPathComponent("gta5"))
        try write("gta5 d3d12", to: paths.pack("gta5").appendingPathComponent("Overlays/gta5/lib/wine/x86_64-windows/d3d12.dll"))
        try write("4.0b2 shared", to: paths.d3dmetal.appendingPathComponent("external/libd3dshared.dylib"))
        try write("4.0b2 d3d11", to: paths.d3dmetal.appendingPathComponent("wine/x86_64-windows/d3d11.dll"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        let fm = FileManager.default
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.engineDLLs.appendingPathComponent("x86_64-unix/d3d11.so").path)
                == paths.d3dmetal.appendingPathComponent("external/libd3dshared.dylib").path)
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.engineDLLs.appendingPathComponent("x86_64-windows/d3d11.dll").path)
                == paths.d3dmetal.appendingPathComponent("wine/x86_64-windows/d3d11.dll").path)
        #expect(read(paths.engineDLLs.appendingPathComponent("x86_64-windows/d3d12.dll")) == "gta5 d3d12")
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.engine.appendingPathComponent("lib/libfreetype.6.dylib").path)
                == paths.frameworks.appendingPathComponent("libfreetype.6.dylib").path)
    }

    @Test func ownD3DMetalEngineBuiltWithTemplateLinksIsReplaced() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let installer = EngineInstaller(runtime: try fakeRuntime(in: dir))
        let paths = GamePaths(profile: .gta5, root: dir.appendingPathComponent("gta5"))
        try write("gta5", to: paths.pack("gta5").appendingPathComponent("Overlays/gta5/marker"))
        try installer.install(for: paths)
        #expect(installer.isCurrent(for: paths))
        try write("v1+gta5+gta5+rockstar+apple-d3dmetal-4.0b2", to: paths.engine.appendingPathComponent(EngineInstaller.markerName))
        #expect(!installer.isCurrent(for: paths))
    }

    @Test func mixedEngineBuiltWithTheOldLayoutIsReplaced() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let installer = EngineInstaller(runtime: try fakeRuntime(in: dir))
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("steam"))
        try installer.install(for: paths)
        #expect(installer.isCurrent(for: paths))
        try write("v1+ntdllfix+cs2+aomretold+controllers", to: paths.engine.appendingPathComponent(EngineInstaller.markerName))
        #expect(!installer.isCurrent(for: paths))
    }

    @Test func currentEngineIsLeftAlone() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let installer = EngineInstaller(runtime: try fakeRuntime(in: dir))
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("aoe4"))
        try installer.install(for: paths)
        try write("touched", to: paths.wine)
        #expect(try installer.install(for: paths) == false)
        #expect(read(paths.wine) == "touched")
    }

    @Test func newRuntimeVersionReplacesTheEngine() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .aoe4, root: dir.appendingPathComponent("aoe4"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir, version: "v1")).install(for: paths)
        try write("touched", to: paths.wine)
        #expect(try EngineInstaller(runtime: try fakeRuntime(in: dir, version: "v2")).install(for: paths) == true)
        #expect(read(paths.wine) == "base wine")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.root.path).filter { $0.hasPrefix("engine-") }
        #expect(leftovers.isEmpty)
    }

    @Test func missingOverlayFailsWithoutLeavingAStage() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let runtime = try fakeRuntime(in: dir)
        try FileManager.default.removeItem(at: runtime.overlay("cs2"))
        let paths = GamePaths(profile: .cs2, root: dir.appendingPathComponent("cs2"))
        #expect(throws: (any Error).self) { try EngineInstaller(runtime: runtime).install(for: paths) }
        #expect(!FileManager.default.fileExists(atPath: paths.engine.path))
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: paths.root.path)) ?? []
        #expect(leftovers.filter { $0.hasPrefix("engine-") }.isEmpty)
    }
}
