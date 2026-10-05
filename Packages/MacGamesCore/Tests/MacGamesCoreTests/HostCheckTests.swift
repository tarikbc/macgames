import Foundation
import Testing
@testable import MacGamesCore

@Suite struct HostCheckTests {
    func helpers(probe: String, sidecar: String) throws -> (URL, RuntimeLayout) {
        let dir = try makeTempDir()
        let helpers = dir.appendingPathComponent("Helpers")
        for (name, body) in [("RosettaProbe", probe), ("x87sidecar", sidecar)] {
            let url = helpers.appendingPathComponent(name)
            try write("#!/bin/sh\n\(body)\n", to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        return (dir, RuntimeLayout(resources: dir.appendingPathComponent("Runtime"), helpers: helpers))
    }

    @Test func workingRosettaAndSidecarAllowTheOptimization() throws {
        let (dir, runtime) = try helpers(probe: "exit 0", sidecar: "echo supported")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try HostCheck(runtime: runtime, runner: ProcessRunner(logDirectory: dir)).run(for: .aoe4)
        #expect(report.optimizationAvailable)
    }

    @Test func failingSidecarProbeTurnsTheOptimizationOff() throws {
        let (dir, runtime) = try helpers(probe: "exit 0", sidecar: "echo unsupported; exit 1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try HostCheck(runtime: runtime, runner: ProcessRunner(logDirectory: dir)).run(for: .aoe4)
        #expect(!report.optimizationAvailable)
        #expect(report.notes.contains { $0.contains("x87sidecar") })
    }

    @Test func profilesWithoutAPinSkipTheSidecarProbe() throws {
        let (dir, runtime) = try helpers(probe: "exit 0", sidecar: "exit 1")
        defer { try? FileManager.default.removeItem(at: dir) }
        let report = try HostCheck(runtime: runtime, runner: ProcessRunner(logDirectory: dir)).run(for: .cs2)
        #expect(!report.optimizationAvailable)
        #expect(report.notes.isEmpty)
    }

    @Test func failingRosettaProbeStopsTheCheck() throws {
        let (dir, runtime) = try helpers(probe: "exit 5", sidecar: "exit 0")
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(throws: SetupError.self) {
            try HostCheck(runtime: runtime, runner: ProcessRunner(logDirectory: dir)).run(for: .aoe4)
        }
    }

    @Test func badArchitectureMeansRosettaIsMissing() {
        let nested = NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EBADARCH))])
        #expect(HostCheck.isBadArchitecture(nested))
        #expect(HostCheck.isBadArchitecture(NSError(domain: NSPOSIXErrorDomain, code: Int(EBADARCH))))
        #expect(!HostCheck.isBadArchitecture(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOENT))))
    }
}
