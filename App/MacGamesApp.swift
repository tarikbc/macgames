import SwiftUI

struct MacGamesApp: App {
    var body: some Scene {
        Window("MacGames", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1040, height: 600)
    }
}
