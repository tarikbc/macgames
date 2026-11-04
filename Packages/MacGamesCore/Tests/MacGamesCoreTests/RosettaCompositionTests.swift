import Foundation
import Testing
@testable import MacGamesCore
@testable import BridgeKit

@Suite struct RosettaCompositionTests {
    @Test func matchingSteamChildKeepsSoftwareFaultsAndEnablesX87OnlyWithNewHelper() {
        let args = ["/app/Helpers/MacGamesBridge", "--cooperative", "/engine/wine", #"C:\game\RelicCardinal.exe"#, "-arg"]
        let fits = GameImage(imageBase: 0x140000000, textStart: 0x140001000, textEnd: 0x14580e95c)
        let env = ["WINEPREFIX": "/prefix", Bridge.optedInKey: "1", "AOE_SOFTFAULT_PC": "0x140001000", "MACGAMES_AOE_COMBINED": "1",
                   "AOELAB_SOFTFAULT_BRIDGE": "1", "AOELAB_CODE_CACHE_GAME": "1", "X87_ALWAYS_NONE": "1"]
        let result = Bridge.decide(arguments: args, environment: env, cwd: "/", isExecutable: { _ in true }) { _ in fits }
        guard case let .exec(path, argv, unset, _) = result else { Issue.record("Expected sidecar"); return }
        #expect(path == "/app/Helpers/x87sidecar")
        #expect(argv.suffix(2) == args.suffix(2))
        #expect(unset == ["X87_ALWAYS_NONE"])
        let rejected = Bridge.decide(arguments: args, environment: env, cwd: "/", isExecutable: { _ in true }) { _ in nil }
        guard case let .exec(loader, _, removed, _) = rejected else { Issue.record("Expected safe fallback"); return }
        #expect(loader == "/engine/wine")
        #expect(removed.contains("MACGAMES_AOE_COMBINED"))
        #expect(removed.contains("AOELAB_SOFTFAULT_BRIDGE"))
        #expect(removed.contains("AOELAB_CODE_CACHE_GAME"))
    }

    @Test func onlyPreparedRuntimeAdvertisesComposedDecoderToSteam() throws {
        let fixture = try FakeEnvironment(.aoe4); defer { fixture.cleanUp() }
        let game = fixture.runtime
        for name in ["RosettaProbe", "x87sidecar", "MacGamesBridge"] {
            let file = game.runtime.helpers.appendingPathComponent(name)
            try write("#!/bin/sh\nexit 0\n", to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        game.settings = LaunchSettings(optimized: true)
        #expect(try game.launchEnvironment()["MACGAMES_AOE_COMBINED"] == nil)
        try write("2\n", to: game.runtime.resources.appendingPathComponent("aoe-performance-v2"))
        let env = try game.launchEnvironment()
        #expect(env["MACGAMES_AOE_COMBINED"] == "1")
        #expect(env["AOELAB_SOFTFAULT_GAME"] == "1")
        #expect(env["AOELAB_CODE_CACHE_GAME"] == "1")
        #expect(env["AOELAB_COUNTERS_DIR"] == nil)
        #expect(env["MTL_HUD_LOG_ENABLED"] == nil)
    }
}
