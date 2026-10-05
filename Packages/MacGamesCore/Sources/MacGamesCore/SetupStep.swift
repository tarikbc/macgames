import Foundation

/// The visible stages of `GameRuntime.prepare()` and `installSteam()`, in order.
public enum SetupStep: Int, CaseIterable, Sendable, Comparable {
    case checkMac, libraries, engine, windows, configure, steam

    public var title: String {
        switch self {
        case .checkMac: "Check this Mac"
        case .libraries: "Get libraries"
        case .engine: "Install the Wine engine"
        case .windows: "Create Windows"
        case .configure: "Configure graphics and controllers"
        case .steam: "Install the game launcher"
        }
    }

    public static func < (a: SetupStep, b: SetupStep) -> Bool { a.rawValue < b.rawValue }
}
