import Foundation
import Darwin
import Testing
import BridgeKit

/// Runs the real MacGamesBridge binary with stand-in sidecar and loader scripts.
@Suite struct BridgeExecutableTests {
    /// SwiftPM puts the bridge next to the test bundle, in whatever build folder
    /// and configuration this run uses.
    static let built: URL = {
        // Swift Testing may run without exposing an .xctest in allBundles.
        // Locate the sibling product even with a custom SwiftPM scratch path.
        var image = Dl_info()
        let executable: URL
        if dladdr(#dsohandle, &image) != 0, let name = image.dli_fname {
            executable = URL(fileURLWithPath: String(cString: name))
        } else {
            executable = URL(fileURLWithPath: CommandLine.arguments[0])
        }
        var folder = executable.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = folder.appendingPathComponent("MacGamesBridge")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
            folder.deleteLastPathComponent()
        }
        let products = Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") }?.bundleURL.deletingLastPathComponent()
        return (products ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(".build/debug"))
            .appendingPathComponent("MacGamesBridge")
    }()

    func stage() throws -> (dir: URL, bridge: URL, loader: URL, game: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("prefix/drive_c/game"), withIntermediateDirectories: true)
        let bridge = dir.appendingPathComponent("MacGamesBridge")
        try FileManager.default.copyItem(at: Self.built, to: bridge)
        let report = "#!/bin/sh\necho \"$(basename \"$0\") $*\"; env | grep -E '^(AOELAB_|AOE_SOFTFAULT_|X87_|MACGAMES_|WINELOADERNOEXEC)' | sort\n"
        for name in ["x87sidecar", "wine"] {
            let url = dir.appendingPathComponent(name)
            try report.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let game = dir.appendingPathComponent("prefix/drive_c/game/RelicCardinal.exe")
        try PEFixture.aoe4(textSize: 0x580d95c).write(to: game)
        return (dir, bridge, dir.appendingPathComponent("wine"), game)
    }

    func run(_ s: (dir: URL, bridge: URL, loader: URL, game: URL), optedIn: Bool = true, composed: Bool = false) throws -> String {
        let p = Process()
        p.executableURL = s.bridge
        p.arguments = ["--cooperative", s.loader.path, "C:\\game\\RelicCardinal.exe", "-dev"]
        p.environment = ["WINEPREFIX": s.dir.appendingPathComponent("prefix").path, "PATH": "/usr/bin:/bin",
                         "AOELAB_SOFTFAULT_GAME": "1", "X87_ALWAYS_NONE": "1", "WINELOADERNOEXEC": "1",
                         // Wine sets the old build's range before it execs the bridge.
                         "AOE_SOFTFAULT_PC": "0x140001000", "AOE_SOFTFAULT_END": "0x1456ddadc"]
        if optedIn { p.environment?[Bridge.optedInKey] = "1" }
        if composed { p.environment?["MACGAMES_AOE_COMBINED"] = "1" }
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test func aFittingImageExecsTheSidecarWithTheEnvironmentIntact() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let out = try run(s)
        #expect(out.hasPrefix("x87sidecar --cooperative \(s.loader.path) C:\\game\\RelicCardinal.exe -dev"))
        #expect(out.contains("AOELAB_SOFTFAULT_GAME=1"))
        #expect(out.contains("X87_ALWAYS_NONE=1"))
    }

    @Test func composedSteamLaunchExecutesX87WithoutLegacyDisable() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let out = try run(s, composed: true)
        #expect(out.hasPrefix("x87sidecar --cooperative"))
        #expect(out.contains("AOELAB_SOFTFAULT_GAME=1"))
        #expect(out.contains("MACGAMES_AOE_COMBINED=1"))
        #expect(!out.contains("X87_ALWAYS_NONE="))
        let fallback = try run(s, optedIn: false, composed: true)
        #expect(fallback == "wine C:\\game\\RelicCardinal.exe -dev\n")
    }

    @Test func aFittingImageExportsItsRangeEnd() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let out = try run(s)
        #expect(out.hasPrefix("x87sidecar --cooperative"))
        #expect(out.contains("AOE_SOFTFAULT_END=0x14580e45c\n"))
        #expect(!out.contains("AOE_SOFTFAULT_END=0x1456ddadc"))
    }

    @Test func aGameThatIsNotAPEFileExecsThePlainLoaderWithOptimizationKeysRemoved() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        try Data("fake game".utf8).write(to: s.game)
        let out = try run(s)
        #expect(out == "wine C:\\game\\RelicCardinal.exe -dev\n")
    }
}
