import Testing
@testable import BridgeKit

@Suite struct BridgePathTests {
    @Test func mapsDriveCToPrefix() {
        #expect(Bridge.unixPath(for: "C:\\Program Files (x86)\\Steam\\steamapps\\common\\Age of Empires IV\\RelicCardinal.exe",
                                prefix: "/r/prefix", cwd: "/x")
                == "/r/prefix/drive_c/Program Files (x86)/Steam/steamapps/common/Age of Empires IV/RelicCardinal.exe")
        #expect(Bridge.unixPath(for: "c:/game.exe", prefix: "/r/prefix", cwd: "/x") == "/r/prefix/drive_c/game.exe")
    }

    @Test func keepsAbsoluteUnixPaths() {
        #expect(Bridge.unixPath(for: "/games/RelicCardinal.exe", prefix: "/r/prefix", cwd: "/x") == "/games/RelicCardinal.exe")
    }

    @Test func joinsRelativePathsToCurrentDirectory() {
        #expect(Bridge.unixPath(for: "RelicCardinal.exe", prefix: "/r/prefix", cwd: "/r/game") == "/r/game/RelicCardinal.exe")
    }
}

@Suite struct BridgeDecisionTests {
    let good = "4c99b868cbec98b2219e135908a31d03c64c7b71f2bbcf1469dab1d7c6df2c9f"
    let args = ["/app/Helpers/MacGamesBridge", "--cooperative", "/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"]

    func env(sha: String?) -> [String: String] {
        var e = ["WINEPREFIX": "/r/prefix", "AOELAB_SOFTFAULT_GAME": "1", "AOE_SOFTFAULT_PC": "0x1", "X87_ALWAYS_NONE": "1",
                 "WINELOADERNOEXEC": "1", "HOME": "/Users/me"]
        e["MACGAMES_OPTIMIZED_SHA256"] = sha
        return e
    }

    @Test func matchingBuildRunsTheSidecarCooperatively() {
        var hashed: String?
        let d = Bridge.decide(arguments: args, environment: env(sha: good), cwd: "/", isExecutable: { _ in true }) { path in hashed = path; return good }
        #expect(hashed == "/r/prefix/drive_c/game/RelicCardinal.exe")
        #expect(d == .exec(path: "/app/Helpers/x87sidecar",
                           argv: ["/app/Helpers/x87sidecar", "--cooperative", "/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"],
                           unset: [], set: [:]))
    }

    @Test func otherBuildRunsThePlainLoaderWithoutOptimizationKeys() {
        let d = Bridge.decide(arguments: args, environment: env(sha: good), cwd: "/") { _ in String(repeating: "0", count: 64) }
        guard case let .exec(path, argv, unset, _) = d else { Issue.record("expected exec, got \(d)"); return }
        #expect(path == "/r/engine/bin/wine")
        #expect(argv == ["/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"])
        #expect(Set(unset) == ["AOELAB_SOFTFAULT_GAME", "AOE_SOFTFAULT_PC", "X87_ALWAYS_NONE", "WINELOADERNOEXEC", "MACGAMES_OPTIMIZED_SHA256"])
    }

    @Test func missingPinFallsBackToThePlainLoader() {
        let d = Bridge.decide(arguments: args, environment: env(sha: nil), cwd: "/") { _ in good }
        guard case let .exec(path, _, _, _) = d else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
    }

    @Test func unreadableGameFallsBackToThePlainLoader() {
        struct Unreadable: Error {}
        let d = Bridge.decide(arguments: args, environment: env(sha: good), cwd: "/") { _ in throw Unreadable() }
        guard case let .exec(path, _, _, _) = d else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
    }

    @Test func nonCooperativeCallsPassThroughToTheSidecar() {
        let d = Bridge.decide(arguments: ["/app/Helpers/MacGamesBridge", "--probe"], environment: [:], cwd: "/") { _ in good }
        #expect(d == .exec(path: "/app/Helpers/x87sidecar", argv: ["/app/Helpers/x87sidecar", "--probe"], unset: [], set: [:]))
    }

    func rangeEnv(end: String?) -> [String: String] {
        var e = env(sha: good)
        e["AOE_SOFTFAULT_PC"] = "0x140001000"
        e["MACGAMES_SOFTFAULT_END"] = end
        return e
    }

    func decide(end: String?) -> BridgeDecision {
        Bridge.decide(arguments: args, environment: rangeEnv(end: end), cwd: "/", isExecutable: { _ in true }) { _ in good }
    }

    @Test func profileEndOverridesWinesRange() {
        #expect(decide(end: "0x1457000f0") == .exec(
            path: "/app/Helpers/x87sidecar",
            argv: ["/app/Helpers/x87sidecar", "--cooperative", "/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"],
            unset: [], set: ["AOE_SOFTFAULT_END": "0x1457000f0"]))
    }

    @Test func missingEndKeepsWinesRange() {
        guard case let .exec(path, _, _, set) = decide(end: nil) else { Issue.record("expected exec"); return }
        #expect(path == "/app/Helpers/x87sidecar")
        #expect(set == [:])
    }

    @Test(arguments: ["abc", "0x", "1457000f0", "0x-1", "0x+1457000f0"])
    func malformedEndFallsBackToThePlainLoader(end: String) {
        guard case let .exec(path, _, _, set) = decide(end: end) else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
        #expect(set == [:])
    }

    @Test(arguments: ["0x140001000", "0x140000fff", "0x146001001"])
    func outOfRangeEndFallsBackToThePlainLoader(end: String) {
        guard case let .exec(path, _, _, _) = decide(end: end) else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
    }

    @Test func largestRangeTheSidecarAcceptsStillRunsIt() {
        guard case let .exec(path, _, _, set) = decide(end: "0x146001000") else { Issue.record("expected exec"); return }
        #expect(path == "/app/Helpers/x87sidecar")
        #expect(set == ["AOE_SOFTFAULT_END": "0x146001000"])
    }

    @Test func cooperativeCallWithoutContextFails() {
        let d = Bridge.decide(arguments: ["/app/Helpers/MacGamesBridge", "--cooperative", "/r/engine/bin/wine"],
                              environment: ["WINEPREFIX": "/r/prefix"], cwd: "/") { _ in good }
        guard case .fail = d else { Issue.record("expected fail, got \(d)"); return }
    }
}
