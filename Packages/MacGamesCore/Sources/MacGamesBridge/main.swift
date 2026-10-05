import BridgeKit
import Darwin
import Foundation

// Wine's patched loader execs this helper for RelicCardinal.exe. It must
// replace itself with x87sidecar or with the plain loader, never return.
let decision = Bridge.decide(arguments: CommandLine.arguments,
                             environment: ProcessInfo.processInfo.environment,
                             cwd: FileManager.default.currentDirectoryPath,
                             hash: Bridge.sha256(ofFileAt:))

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("MacGamesBridge: \(message)\n".utf8))
    exit(78)
}

switch decision {
case .fail(let message):
    fail(message)
case let .exec(path, argv, unset):
    if !unset.isEmpty {
        FileHandle.standardError.write(Data("MacGamesBridge: this game build is not the optimized one; using the standard runtime.\n".utf8))
    }
    for key in unset { unsetenv(key) }
    let pointers = argv.map { strdup($0) } + [nil]
    _ = pointers.withUnsafeBufferPointer { execv(path, $0.baseAddress!) }
    fail("could not start \(path): \(String(cString: strerror(errno)))")
}
