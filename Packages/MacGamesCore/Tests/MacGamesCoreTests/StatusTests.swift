import Foundation
import Testing
@testable import MacGamesCore

@Suite struct AppManifestTests {
    let installed = """
    "AppState"
    {
    \t"appid"\t\t"1466860"
    \t"Universe"\t\t"1"
    \t"name"\t\t"Age of Empires IV: Anniversary Edition"
    \t"StateFlags"\t\t"4"
    \t"installdir"\t\t"Age of Empires IV"
    \t"buildid"\t\t"24231237"
    }
    """

    @Test func readsTopLevelKeys() {
        let m = AppManifest(text: installed)
        #expect(m["appid"] == "1466860")
        #expect(m["installdir"] == "Age of Empires IV")
        #expect(m["buildid"] == "24231237")
    }

    @Test func fullyInstalledNeedsMatchingIdFolderAndStateFour() {
        #expect(AppManifest(text: installed).isFullyInstalled(.aoe4))
        #expect(!AppManifest(text: installed).isFullyInstalled(.cs2))
        let downloading = installed.replacingOccurrences(of: "\"StateFlags\"\t\t\"4\"", with: "\"StateFlags\"\t\t\"1026\"")
        #expect(!AppManifest(text: downloading).isFullyInstalled(.aoe4))
    }

    @Test func ignoresNestedSections() {
        let text = installed.replacingOccurrences(of: "}", with: "\t\"UserConfig\"\n\t{\n\t\t\"StateFlags\"\t\t\"0\"\n\t}\n}")
        #expect(AppManifest(text: text)["StateFlags"] == "4")
    }
}

@Suite struct GameProcessLogTests {
    let start = "[2026-10-05 10:00:00] AppID 1466860 adding PID 412 as a tracked process \"C:\\Program Files (x86)\\Steam\\steamapps\\common\\Age of Empires IV\\RelicCardinal.exe\""

    @Test func trackedGameIsRunning() {
        #expect(GameProcessLog.isRunning(.aoe4, log: start))
    }

    @Test func removedGameIsNotRunning() {
        let log = start + "\n[2026-10-05 11:00:00] Game 1466860 removed: Remove 1466860 from running list\n"
        #expect(!GameProcessLog.isRunning(.aoe4, log: log))
    }

    @Test func untrackedPidIsNotRunning() {
        let log = start + "\n[2026-10-05 11:00:00] AppID 1466860 no longer tracking PID 412, exit code 0\n"
        #expect(!GameProcessLog.isRunning(.aoe4, log: log))
    }

    @Test func otherAppsDoNotCount() {
        #expect(!GameProcessLog.isRunning(.cs2, log: start))
    }

    @Test func helperProcessesOfTheSameAppDoNotCount() {
        let helper = "AppID 1466860 adding PID 500 as a tracked process \"C:\\...\\CrashReporter.exe\""
        #expect(!GameProcessLog.isRunning(.aoe4, log: helper))
    }
}

@Suite struct LiveProcessTests {
    @Test func findsARunningProcessUnderAFolder() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        // macOS kills relocated copies of Apple's own binaries, so build a fresh one.
        let copy = dir.appendingPathComponent("bin/sleep")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let source = dir.appendingPathComponent("sleep.c")
        try write("#include <unistd.h>\nint main(void){sleep(10);return 0;}\n", to: source)
        try ProcessRunner(logDirectory: dir).run(URL(fileURLWithPath: "/usr/bin/cc"), [source.path, "-o", copy.path])
        #expect(LiveProcesses.paths(under: dir).isEmpty)
        let p = Process(); p.executableURL = copy; try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(LiveProcesses.paths(under: dir).map(\.lastPathComponent) == ["sleep"])
    }
}

@Suite struct ProcessSnapshotTests {
    let engine = URL(fileURLWithPath: "/r/steam/engine")
    var snapshot: ProcessSnapshot {
        ProcessSnapshot(entries: [
            .init(pid: 10, path: "/r/steam/engine/bin/wineserver", argv0: "/r/steam/engine/bin/wineserver"),
            .init(pid: 11, path: "/r/steam/engine/bin/wine-preloader", argv0: #"C:\Program Files (x86)\Steam\steamapps\common\Game\Game.EXE"#),
            .init(pid: 12, path: "/r/rockstar/engine/bin/wine-preloader", argv0: #"C:\Other\Other.exe"#),
        ])
    }

    @Test func queriesFilterOneScanByEngineFolder() {
        #expect(snapshot.paths(under: engine).map(\.path) == ["/r/steam/engine/bin/wineserver", "/r/steam/engine/bin/wine-preloader"])
        #expect(snapshot.isRunning(executable: "game.exe", under: engine))
        #expect(!snapshot.isRunning(executable: "Other.exe", under: engine), "another environment's process")
    }

    @Test func stateComesFromTheSnapshotWithoutAScan() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let runtime = GameRuntime(profile: .cs2, root: dir, runtime: RuntimeLayout(resources: dir, helpers: dir))
        let server = runtime.paths.wineserver.resolvingSymlinksInPath().path
        let live = ProcessSnapshot(entries: [.init(pid: 1, path: server, argv0: server)])
        #expect(runtime.isSessionRunning(using: live))
        #expect(!runtime.isSessionRunning(using: ProcessSnapshot(entries: [])))
    }
}
