import Foundation

public struct CommandFailure: Error, CustomStringConvertible {
    public let executable: String
    public let status: Int32
    public let output: String
    public let log: URL
    public var description: String {
        "\(executable) failed (exit \(status)). Log: \(log.path)\n\(output.suffix(2000))"
    }
}

public struct CommandTimeout: Error, CustomStringConvertible {
    public let executable: String
    public let log: URL
    public var description: String { "\(executable) did not finish in time. Log: \(log.path)" }
}

/// Runs a child process to completion. Output goes to a per-command log file
/// rather than a pipe, so a chatty Wine process can never block on a full pipe.
public struct ProcessRunner: Sendable {
    public let logDirectory: URL

    /// A handle that always writes at the end of the file, even when several
    /// processes share it (for example two Steam launches in one session).
    public static func appendHandle(for url: URL) throws -> FileHandle {
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path]) }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    public init(logDirectory: URL) { self.logDirectory = logDirectory }

    @discardableResult
    public func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                    workingDirectory: URL? = nil, timeout: TimeInterval = 120,
                    allowedStatuses: Set<Int32> = [0]) throws -> String {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let log = logDirectory.appendingPathComponent("command-\(executable.lastPathComponent)-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: log.path, contents: nil)
        let handle = try FileHandle(forWritingTo: log)
        defer { try? handle.close() }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        let done = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in done.signal() }
        try process.run()

        if done.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                done.wait()
            }
            throw CommandTimeout(executable: executable.lastPathComponent, log: log)
        }
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard allowedStatuses.contains(process.terminationStatus) else {
            throw CommandFailure(executable: executable.lastPathComponent, status: process.terminationStatus,
                                 output: output, log: log)
        }
        return output
    }
}
