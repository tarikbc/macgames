import BridgeKit
import Foundation

/// Whether the x87sidecar optimization applies to the next launch, and why not.
public enum OptimizationStatus: Sendable, Equatable {
    /// The profile has no optimization.
    case notApplicable
    /// The user turned it off.
    case off
    /// The game is not installed yet, so its build is unknown.
    case waitingForGame
    /// The installed exe's code layout does not fit the software-fault hook.
    case unsupportedBuild
    /// x87sidecar does not support this Mac's Rosetta version.
    case unsupportedRosetta
    /// It fits, but nobody has played this build with the optimization yet.
    case untestedBuild
    case active

    /// Wine's AOE_SOFTFAULT_PC; the app cannot read Wine's environment.
    public static let softfaultStart: UInt64 = 0x140001000

    public static func evaluate(_ profile: GameProfile, enabled: Bool, image: GameImage?, executableSHA256: String?,
                                sidecarSupported: Bool) -> OptimizationStatus {
        guard let optimization = profile.rosettaOptimization else { return .notApplicable }
        guard enabled else { return .off }
        guard image != nil || executableSHA256 != nil else { return .waitingForGame }
        guard image?.softfaultEnd(start: softfaultStart) != nil else { return .unsupportedBuild }
        guard sidecarSupported else { return .unsupportedRosetta }
        guard let sha = executableSHA256, optimization.testedExecutableSHA256s.contains(sha) else { return .untestedBuild }
        return .active
    }
}
