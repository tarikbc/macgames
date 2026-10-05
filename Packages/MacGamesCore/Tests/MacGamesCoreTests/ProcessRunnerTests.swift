import Foundation
import Testing
@testable import MacGamesCore

@Suite struct ProcessRunnerTests {
    @Test func returnsCombinedOutputAndKeepsALog() throws {
        let logs = try makeTempDir(); defer { try? FileManager.default.removeItem(at: logs) }
        let runner = ProcessRunner(logDirectory: logs)
        let out = try runner.run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo out; echo err >&2"])
        #expect(out.contains("out"))
        #expect(out.contains("err"))
        let files = try FileManager.default.contentsOfDirectory(atPath: logs.path)
        #expect(files.count == 1)
    }

    @Test func passesEnvironmentAndWorkingDirectory() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let out = try ProcessRunner(logDirectory: dir).run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo $MG_X; pwd"],
                                                         environment: ["MG_X": "hello"], workingDirectory: dir)
        #expect(out.contains("hello"))
        #expect(out.contains(dir.resolvingSymlinksInPath().lastPathComponent))
    }

    @Test func nonZeroExitThrowsWithTheOutputTail() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        #expect {
            try ProcessRunner(logDirectory: dir).run(URL(fileURLWithPath: "/bin/sh"), ["-c", "echo boom; exit 3"])
        } throws: { error in
            guard let failure = error as? CommandFailure else { return false }
            return failure.status == 3 && failure.output.contains("boom")
        }
    }

    @Test func allowedStatusesDoNotThrow() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        _ = try ProcessRunner(logDirectory: dir).run(URL(fileURLWithPath: "/bin/sh"), ["-c", "exit 1"], allowedStatuses: [0, 1])
    }

    @Test func timeoutKillsTheProcess() throws {
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let start = Date()
        #expect(throws: CommandTimeout.self) {
            try ProcessRunner(logDirectory: dir).run(URL(fileURLWithPath: "/bin/sleep"), ["30"], timeout: 0.5)
        }
        #expect(Date().timeIntervalSince(start) < 5)
    }
}
