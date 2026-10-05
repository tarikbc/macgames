import AppKit
import MacGamesCore

extension LaunchContext {
    /// The main display as games should see it: size in points, and whether it has a notch.
    @MainActor static func mainDisplay() -> LaunchContext {
        let size = CGDisplayBounds(CGMainDisplayID()).size
        let notch = (NSScreen.main?.safeAreaInsets.top ?? 0) > 0
        return LaunchContext(width: Int(size.width), height: Int(size.height), hasNotch: notch)
    }
}
