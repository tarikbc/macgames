import SwiftUI

struct MacGamesApp: App {
    var body: some Scene {
        Window("MacGames", id: "main") {
            LibraryView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 740)
    }
}
