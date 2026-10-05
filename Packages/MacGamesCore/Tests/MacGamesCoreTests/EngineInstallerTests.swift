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
        try write("""
        {"lib/libfreetype.6.dylib": "libfreetype.6.dylib",
         "lib/wine/x86_64-windows/d3d11.dll": "renderer/d3dmetal/wine/x86_64-windows/d3d11.dll"}
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
        #expect(read(paths.engine.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")) == "cs2 d3d11 64")
        #expect(read(paths.engine.appendingPathComponent("lib/wine/x86_64-unix/winebus.so")) == "controller winebus")
        #expect(read(paths.engine.appendingPathComponent("lib/wine/x86_64-unix/ntdll.so")) == "fixed ntdll")
        #expect(GameEnvironment.steam.engineOverlays == ["ntdllfix", "cs2", "aomretold", "controllers"])
    }

    @Test func overlayFilesWinOverDependencyLinks() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let paths = GamePaths(profile: .cs2, root: dir.appendingPathComponent("cs2"))
        try EngineInstaller(runtime: try fakeRuntime(in: dir)).install(for: paths)
        let dll = paths.engine.appendingPathComponent("lib/wine/x86_64-windows/d3d11.dll")
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: dll.path)) == nil)
        #expect(read(dll) == "cs2 d3d11 64")
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
