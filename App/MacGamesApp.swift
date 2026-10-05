import Sparkle
import SwiftUI

struct MacGamesApp: App {
    /// Checks the appcast of this repository's releases for a newer, signed MacGames.
    private let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var body: some Scene {
        Window("MacGames", id: "main") {
            LibraryView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates(nil) }
            }
        }
    }
}
