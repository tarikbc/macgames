import Foundation

public struct HostReport: Sendable {
    public let optimizationAvailable: Bool
    public let notes: [String]
}

/// Confirms this Mac can run the x86_64 engine before any setup work starts.
public struct HostCheck: Sendable {
    public let runtime: RuntimeLayout
    public let runner: ProcessRunner

    public init(runtime: RuntimeLayout, runner: ProcessRunner) {
        self.runtime = runtime
        self.runner = runner
    }

    public static let rosettaMissingMessage =
        "Rosetta is not installed. Install it with: softwareupdate --install-rosetta --agree-to-license"

    public func run(for profile: GameProfile) throws -> HostReport {
        #if !arch(arm64)
        throw SetupError("MacGames needs an Apple Silicon Mac.")
        #endif
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26 else {
            throw SetupError("MacGames needs macOS 26 or later.")
        }
        do {
            try runner.run(runtime.rosettaProbe, [], timeout: 30)
        } catch let error where Self.isBadArchitecture(error) {
            throw SetupError(Self.rosettaMissingMessage)
        } catch {
            throw SetupError("The Rosetta check failed: \(error)")
        }

        guard profile.optimizedExecutableSHA256 != nil else { return HostReport(optimizationAvailable: false, notes: []) }
        do {
            try runner.run(runtime.sidecar, ["--probe"], timeout: 25)
            return HostReport(optimizationAvailable: true, notes: [])
        } catch {
            return HostReport(optimizationAvailable: false,
                              notes: ["x87sidecar does not support this Rosetta version, so the game runs without the optimization."])
        }
    }

    /// Foundation reports a missing Rosetta as POSIX EBADARCH, sometimes nested.
    public static func isBadArchitecture(_ error: any Error) -> Bool {
        var current: NSError? = error as NSError
        while let e = current {
            if e.domain == NSPOSIXErrorDomain && e.code == Int(EBADARCH) { return true }
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
