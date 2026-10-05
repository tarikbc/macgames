import Foundation
import Testing
import BridgeKit

/// Runs the real MacGamesBridge binary with stand-in sidecar and loader scripts.
@Suite struct BridgeExecutableTests {
    /// SwiftPM puts the bridge next to the test bundle, in whatever build folder
    /// and configuration this run uses.
    static let built: URL = {
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
        let report = "#!/bin/sh\necho \"$(basename \"$0\") $*\"; env | grep -E '^(AOELAB_|X87_|MACGAMES_|WINELOADERNOEXEC)' | sort\n"
        for name in ["x87sidecar", "wine"] {
            let url = dir.appendingPathComponent(name)
            try report.write(to: url, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let game = dir.appendingPathComponent("prefix/drive_c/game/RelicCardinal.exe")
        try Data("fake game".utf8).write(to: game)
        return (dir, bridge, dir.appendingPathComponent("wine"), game)
    }

    func run(_ s: (dir: URL, bridge: URL, loader: URL, game: URL), pin: String) throws -> String {
        let p = Process()
        p.executableURL = s.bridge
        p.arguments = ["--cooperative", s.loader.path, "C:\\game\\RelicCardinal.exe", "-dev"]
        p.environment = ["WINEPREFIX": s.dir.appendingPathComponent("prefix").path, "PATH": "/usr/bin:/bin",
                         "AOELAB_SOFTFAULT_GAME": "1", "X87_ALWAYS_NONE": "1", "WINELOADERNOEXEC": "1",
                         Bridge.pinKey: pin]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
        try p.run(); p.waitUntilExit()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test func matchingBuildExecsTheSidecarWithTheEnvironmentIntact() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let out = try run(s, pin: try Bridge.sha256(ofFileAt: s.game.path))
        #expect(out.hasPrefix("x87sidecar --cooperative \(s.loader.path) C:\\game\\RelicCardinal.exe -dev"))
        #expect(out.contains("AOELAB_SOFTFAULT_GAME=1"))
        #expect(out.contains("X87_ALWAYS_NONE=1"))
    }

    @Test func otherBuildExecsThePlainLoaderWithOptimizationKeysRemoved() throws {
        let s = try stage(); defer { try? FileManager.default.removeItem(at: s.dir) }
        let out = try run(s, pin: String(repeating: "0", count: 64))
        #expect(out == "wine C:\\game\\RelicCardinal.exe -dev\n")
    }
}
