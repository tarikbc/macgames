import Foundation
import Testing
@testable import MacGamesCore

/// Builds a tiny native program; macOS kills relocated copies of Apple's binaries.
func compileSleeper(to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let source = url.deletingLastPathComponent().appendingPathComponent("sleeper-\(UUID().uuidString).c")
    try write("#include <unistd.h>\nint main(void){sleep(10);return 0;}\n", to: source)
    defer { try? FileManager.default.removeItem(at: source) }
    try ProcessRunner(logDirectory: FileManager.default.temporaryDirectory).run(URL(fileURLWithPath: "/usr/bin/cc"), [source.path, "-o", url.path])
}

@Suite struct SessionProbeTests {
    func runtime(_ dir: URL) -> GameRuntime {
        GameRuntime(profile: .aoe4, root: dir.appendingPathComponent("aoe4"),
                    runtime: RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: dir.appendingPathComponent("Helpers")),
                    downloadCache: dir.appendingPathComponent("downloads"))
    }

    @Test func idleEngineIsNotRunningAndWritesNoLogs() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let game = runtime(dir)
        try compileSleeper(to: game.paths.wineserver)
        #expect(!game.isSessionRunning())
        let logs = (try? FileManager.default.contentsOfDirectory(atPath: game.paths.logs.path)) ?? []
        #expect(logs.isEmpty)
    }

    @Test func liveWineserverMeansTheSessionRuns() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let game = runtime(dir)
        try compileSleeper(to: game.paths.wineserver)
        let p = Process(); p.executableURL = game.paths.wineserver; try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(game.isSessionRunning())
    }
}

@Suite struct StaleGameLogTests {
    @Test func killedSessionDoesNotLeaveTheGameRunning() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let p = GamePaths(profile: .aoe4, root: dir)
        try write("runtime-v1\n", to: p.runtimeReady); try write("exe", to: p.steamExe)
        try write("\"AppState\"\n{\n\t\"appid\"\t\t\"1466860\"\n\t\"StateFlags\"\t\t\"4\"\n\t\"installdir\"\t\t\"Age of Empires IV\"\n}\n", to: p.appManifest)
        try write("game", to: p.gameExe)
        let log = p.steamDir.appendingPathComponent("logs/gameprocess_log.txt")
        // A session killed with wineserver -k never writes the remove line.
        try write("[2026-10-04 23:29:20] AppID 1466860 adding PID 1048 as a tracked process \"\"C:\\Program Files (x86)\\Steam\\steamapps\\common\\Age of Empires IV\\RelicCardinal.exe\"\"\n", to: log)
        try SteamSession.begin(fingerprint: "f", paths: p)
        #expect(GameState.derive(p, sessionRunning: true) == .ready)

        let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd()
        handle.write(Data("[2026-10-05 09:00:00] AppID 1466860 adding PID 2000 as a tracked process \"\"C:\\x\\RelicCardinal.exe\"\"\n".utf8))
        try handle.close()
        #expect(GameState.derive(p, sessionRunning: true) == .running)
        #expect(SteamSession.load(p)?.fingerprint == "f")
    }

    @Test func realSteamLineFormatIsRecognized() {
        let line = "[2026-10-04 23:29:20] AppID 1466860 adding PID 1048 as a tracked process \"\"C:\\Program Files (x86)\\Steam\\steamapps\\common\\Age of Empires IV\\RelicCardinal.exe\"\""
        #expect(GameProcessLog.isRunning(.aoe4, log: line))
    }
}

@Suite struct EngineRefreshTests {
    @Test func newEngineReappliesTheGraphicsLibraries() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        func runtime(_ version: String, winemetal: String) throws -> RuntimeLayout {
            let res = dir.appendingPathComponent("Runtime-\(version)")
            try write("wine", to: res.appendingPathComponent("Engine/bin/wine"))
            try write(winemetal, to: res.appendingPathComponent("Overlays/cs2/lib/wine/x86_64-windows/winemetal.dll"))
            try write(winemetal + " 32", to: res.appendingPathComponent("Overlays/cs2/lib/wine/i386-windows/winemetal.dll"))
            try write("so", to: res.appendingPathComponent("Overlays/controllers/lib/wine/x86_64-unix/winebus.so"))
            try write("{}", to: res.appendingPathComponent("dependency-links.json"))
            try write(version, to: res.appendingPathComponent("VERSION"))
            return RuntimeLayout(resources: res, helpers: dir.appendingPathComponent("Helpers"))
        }
        let root = dir.appendingPathComponent("cs2")
        let v1 = GameRuntime(profile: .cs2, root: root, runtime: try runtime("v1", winemetal: "metal v1"), downloadCache: dir)
        try v1.ensureEngine()
        let system32 = v1.paths.prefix.appendingPathComponent("drive_c/windows/system32/winemetal.dll")
        try write("metal v1", to: system32)

        let v2 = GameRuntime(profile: .cs2, root: root, runtime: try runtime("v2", winemetal: "metal v2"), downloadCache: dir)
        try v2.ensureEngine()
        #expect(read(system32) == "metal v2")
        #expect(read(v2.paths.prefix.appendingPathComponent("drive_c/windows/syswow64/winemetal.dll")) == "metal v2 32")
    }
}

@Suite struct RestartPolicyTests {
    @Test func onlyAGameLaunchRestartsAMismatchedSteam() {
        #expect(SteamLaunch.needsRestart(.play([]), sessionRunning: true, fingerprintMatches: false))
        #expect(!SteamLaunch.needsRestart(.open, sessionRunning: true, fingerprintMatches: false))
        #expect(!SteamLaunch.needsRestart(.install, sessionRunning: true, fingerprintMatches: false))
        #expect(!SteamLaunch.needsRestart(.play([]), sessionRunning: true, fingerprintMatches: true))
        #expect(!SteamLaunch.needsRestart(.play([]), sessionRunning: false, fingerprintMatches: false))
    }
}

@Suite struct SharedDownloadTests {
    @Test func aFileAnotherSetupAlreadyPlacedIsAccepted() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("file.bin"), partial = dir.appendingPathComponent(".file.partial")
        try write("same", to: target); try write("same", to: partial)
        let pin = sha256Hex(Data("same".utf8))
        #expect(try Downloader(cache: dir).commit(partial, to: target, pin: pin) == target)
        #expect(read(target) == "same")
    }
}

@Suite struct PendingUpdateTests {
    @Test func installedGameWithAQueuedUpdateIsStillInstalled() {
        let text = "\"AppState\"\n{\n\t\"appid\"\t\t\"1466860\"\n\t\"StateFlags\"\t\t\"6\"\n\t\"installdir\"\t\t\"Age of Empires IV\"\n}\n"
        #expect(AppManifest(text: text).isFullyInstalled(.aoe4))
    }
}
