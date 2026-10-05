import AppKit
import MacGamesCore

extension LaunchContext {
    /// The main display as games should see it: size in points, and whether it has a notch.
    /// Uses the menu-bar display, where Wine places fullscreen games, for both size and notch.
    @MainActor static func mainDisplay() -> LaunchContext {
        guard let screen = NSScreen.screens.first else {
            let size = CGDisplayBounds(CGMainDisplayID()).size
            return LaunchContext(width: Int(size.width), height: Int(size.height))
        }
        return LaunchContext(width: Int(screen.frame.width), height: Int(screen.frame.height),
                             hasNotch: screen.safeAreaInsets.top > 0, topInset: screen.safeAreaInsets.top)
    }
}
