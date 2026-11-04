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
    let args = ["/app/Helpers/MacGamesBridge", "--cooperative", "/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"]
    let sidecarArgv = ["/app/Helpers/x87sidecar", "--cooperative", "/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"]
    let fits = GameImage(imageBase: 0x140000000, textStart: 0x140001000, textEnd: 0x14580e95c)

    /// What Wine hands the bridge: the old build's range, plus MacGames' opt-in.
    func env(optedIn: Bool = true) -> [String: String] {
        var e = ["WINEPREFIX": "/r/prefix", "AOELAB_SOFTFAULT_GAME": "1", "AOE_SOFTFAULT_PC": "0x140001000",
                 "AOE_SOFTFAULT_END": "0x1456ddadc", "X87_ALWAYS_NONE": "1", "WINELOADERNOEXEC": "1", "HOME": "/Users/me"]
        if optedIn { e[Bridge.optedInKey] = "1" }
        return e
    }

    func decide(_ environment: [String: String], image: (String) throws -> GameImage?) -> BridgeDecision {
        Bridge.decide(arguments: args, environment: environment, cwd: "/", isExecutable: { _ in true }, image: image)
    }

    func loaderPath(_ d: BridgeDecision) -> String? {
        guard case let .exec(path, _, _, set) = d, set.isEmpty else { return nil }
        return path
    }

    @Test func anyBuildWithAFittingHeaderRunsTheSidecar() {
        var read: String?
        let d = decide(env()) { read = $0; return fits }
        #expect(read == "/r/prefix/drive_c/game/RelicCardinal.exe")
        #expect(d == .exec(path: "/app/Helpers/x87sidecar", argv: sidecarArgv, unset: [], set: ["AOE_SOFTFAULT_END": "0x14580e45c"]))
    }

    @Test func aNewerBuildGetsItsOwnRange() {
        let d = decide(env()) { _ in GameImage(imageBase: 0x140000000, textStart: 0x140001000, textEnd: 0x1459000fc) }
        #expect(d == .exec(path: "/app/Helpers/x87sidecar", argv: sidecarArgv, unset: [], set: ["AOE_SOFTFAULT_END": "0x1458ffbfc"]))
    }

    @Test func movedTextFallsBackToThePlainLoader() {
        let d = decide(env()) { _ in GameImage(imageBase: 0x140001000, textStart: 0x140002000, textEnd: 0x14580f95c) }
        guard case let .exec(path, argv, unset, set) = d else { Issue.record("expected exec, got \(d)"); return }
        #expect(path == "/r/engine/bin/wine")
        #expect(argv == ["/r/engine/bin/wine", "C:\\game\\RelicCardinal.exe", "-arg"])
        #expect(Set(unset) == ["AOELAB_SOFTFAULT_GAME", "AOE_SOFTFAULT_PC", "AOE_SOFTFAULT_END", "X87_ALWAYS_NONE",
                               "WINELOADERNOEXEC", Bridge.optedInKey])
        #expect(set == [:])
    }

    @Test func oversizedTextFallsBackToThePlainLoader() {
        let d = decide(env()) { _ in GameImage(imageBase: 0x140000000, textStart: 0x140001000, textEnd: 0x146001501) }
        #expect(loaderPath(d) == "/r/engine/bin/wine")
    }

    @Test func unreadableImageFallsBackToThePlainLoader() {
        struct Unreadable: Error {}
        #expect(loaderPath(decide(env()) { _ in throw Unreadable() }) == "/r/engine/bin/wine")
        #expect(loaderPath(decide(env()) { _ in nil }) == "/r/engine/bin/wine")
    }

    @Test func oldSessionWithoutTheOptInKeyRunsThePlainLoader() {
        var e = env(optedIn: false)
        e["MACGAMES_OPTIMIZED_SHA256"] = "4c99b868cbec98b2219e135908a31d03c64c7b71f2bbcf1469dab1d7c6df2c9f"
        let d = decide(e) { _ in fits }
        guard case let .exec(path, _, unset, _) = d else { Issue.record("expected exec"); return }
        #expect(path == "/r/engine/bin/wine")
        #expect(unset.contains("MACGAMES_OPTIMIZED_SHA256"))
    }

    @Test(arguments: ["1", "0x", "0x14000100g", ""])
    func malformedWinePCFallsBackToThePlainLoader(pc: String) {
        var e = env()
        e["AOE_SOFTFAULT_PC"] = pc
        #expect(loaderPath(decide(e) { _ in fits }) == "/r/engine/bin/wine")
    }

    @Test func nonCooperativeCallsPassThroughToTheSidecar() {
        let d = Bridge.decide(arguments: ["/app/Helpers/MacGamesBridge", "--probe"], environment: [:], cwd: "/") { _ in fits }
        #expect(d == .exec(path: "/app/Helpers/x87sidecar", argv: ["/app/Helpers/x87sidecar", "--probe"], unset: [], set: [:]))
    }

    @Test func cooperativeCallWithoutContextFails() {
        let d = Bridge.decide(arguments: ["/app/Helpers/MacGamesBridge", "--cooperative", "/r/engine/bin/wine"],
                              environment: ["WINEPREFIX": "/r/prefix"], cwd: "/") { _ in fits }
        guard case .fail = d else { Issue.record("expected fail, got \(d)"); return }
    }
}
