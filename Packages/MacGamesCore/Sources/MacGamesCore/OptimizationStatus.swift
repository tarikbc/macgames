import Foundation

/// Whether the x87sidecar optimization applies to the next launch, and why not.
public enum OptimizationStatus: Sendable, Equatable {
    /// The profile has no optimization.
    case notApplicable
    /// The user turned it off.
    case off
    /// The game is not installed yet, so its build is unknown.
    case waitingForGame
    /// The installed game is not the build the optimization was made for.
    case otherBuild
    /// x87sidecar does not support this Mac's Rosetta version.
    case unsupportedRosetta
    case active

    public static func evaluate(_ profile: GameProfile, enabled: Bool, executableSHA256: String?,
                                sidecarSupported: Bool) -> OptimizationStatus {
        guard let pin = profile.optimizedExecutableSHA256 else { return .notApplicable }
        guard enabled else { return .off }
        guard let actual = executableSHA256 else { return .waitingForGame }
        guard actual == pin else { return .otherBuild }
        return sidecarSupported ? .active : .unsupportedRosetta
    }
}
