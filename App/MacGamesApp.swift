import SwiftUI

struct MacGamesApp: App {
    var body: some Scene {
        WindowGroup("MacGames") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 600)
    }
}
