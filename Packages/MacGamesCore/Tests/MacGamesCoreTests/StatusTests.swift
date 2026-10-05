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
        let copy = dir.appendingPathComponent("bin/sleep")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: copy)
        #expect(LiveProcesses.paths(under: dir).isEmpty)
        let p = Process(); p.executableURL = copy; p.arguments = ["10"]; try p.run()
        defer { p.terminate(); p.waitUntilExit() }
        Thread.sleep(forTimeInterval: 0.2)
        #expect(LiveProcesses.paths(under: dir).map(\.lastPathComponent) == ["sleep"])
    }
}
