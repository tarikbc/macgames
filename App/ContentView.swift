import MacGamesCore
import SwiftUI

struct ContentView: View {
    @State private var games = GameProfile.all.map { GameModel(profile: $0) }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(games) { GamePanel(game: $0) }
        }
        .background(.black)
        .ignoresSafeArea()
        .frame(minWidth: 860, minHeight: 520)
        .task {
            while !Task.isCancelled {
                for game in games { await game.refresh() }
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}

extension GameProfile {
    var accent: Color {
        switch id {
        case "aoe4": Color(red: 0.78, green: 0.25, blue: 0.23)
        default: Color(red: 0.91, green: 0.64, blue: 0.23)
        }
    }

    var artwork: URL {
        URL(string: "https://shared.akamai.steamstatic.com/store_item_assets/steam/apps/\(steamAppID)/library_hero.jpg")!
    }
}

struct GamePanel: View {
    let game: GameModel

    var body: some View {
        // The artwork sits in an overlay so its fill size never widens the panel.
        Color.clear
            .overlay { artwork }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.55), .black.opacity(0.92)],
                               startPoint: .center, endPoint: .bottom)
            }
            .clipped()
            .overlay(alignment: .bottomLeading) { details.padding(28) }
            .environment(\.colorScheme, .dark)
    }

    private var artwork: some View {
        AsyncImage(url: game.profile.artwork) { phase in
            if let image = phase.image {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                game.profile.accent.opacity(0.35)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(game.profile.title)
                .font(.system(size: 34, weight: .heavy).width(.condensed))
                .foregroundStyle(.white)
            statusLine
            HStack(spacing: 10) {
                Button(action: game.primaryAction) {
                    Text(game.state.actionTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(minWidth: 96)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(game.state == .running ? .gray : game.profile.accent)
                .controlSize(.large)
                .disabled(game.busy)
                .keyboardShortcut(game.profile.id == "aoe4" ? "1" : "2", modifiers: .command)

                GameMenu(game: game)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .confirmationDialog("Stop \(game.profile.title)?", isPresented: Bindable(game).confirmingStop) {
            Button("Stop the game and Steam", role: .destructive, action: game.stop)
        } message: {
            Text("The game closes at once. Progress since your last save is lost.")
        }
    }

    @ViewBuilder private var statusLine: some View {
        if let error = game.error {
            Text(error)
                .font(.callout)
                .foregroundStyle(Color(red: 1, green: 0.55, blue: 0.5))
                .lineLimit(4)
                .textSelection(.enabled)
        } else {
            HStack(spacing: 8) {
                if game.busy { ProgressView().controlSize(.small) }
                Text(game.activity ?? game.state.summary)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
            }
        }
    }
}

struct GameMenu: View {
    @Bindable var game: GameModel

    var body: some View {
        Menu {
            Button("Open Steam", action: game.openSteam).disabled(game.state == .notSetUp || game.state == .needsSteam)
            Button("Stop Steam and the game", action: game.requestStop)
            Divider()
            Toggle("Performance HUD", isOn: $game.settings.hud)
            if game.profile.optimizedExecutableSHA256 != nil {
                Toggle("x87 optimization", isOn: $game.settings.optimized)
            }
            if game.profile.graphics == .dxmt {
                Button("Reset window size on next launch", action: game.resetDisplay)
            }
            Divider()
            Button("Show logs", action: game.showLogs)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22, height: 22)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(game.busy)
        .help("More actions")
    }
}
