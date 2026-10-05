import MacGamesCore
import SwiftUI

struct LibraryView: View {
    @State private var library = LibraryModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(library: library)
                .frame(width: 252)
            if let game = library.selected {
                GameDetailView(game: game)
                    .id(game.id)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .opacity.combined(with: .offset(y: 18)).combined(with: .scale(scale: 0.985, anchor: .top)),
                        removal: .opacity))
            }
        }
        .background { Backdrop(game: library.selected) }
        .ignoresSafeArea()
        .frame(minWidth: 980, minHeight: 620)
        .environment(\.colorScheme, .dark)
        .task { await library.poll() }
        .background {
            // ⌘1…⌘9 select a game by its place in the list.
            ForEach(Array(library.games.prefix(9).enumerated()), id: \.offset) { index, _ in
                Button("") { withAnimation(Motion.switchGame) { library.select(index: index) } }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .hidden()
            }
        }
    }
}

/// The selected game's hero art, blurred into the whole window.
private struct Backdrop: View {
    let game: GameModel?

    var body: some View {
        ZStack {
            Color.black
            if let game {
                ArtImage(url: game.profile.artwork.hero, focus: game.profile.heroFocus)
                    .blur(radius: 80)
                    .saturation(1.25)
                    .opacity(0.55)
                    .id(game.id)
                    .transition(.opacity)
            }
            Color.black.opacity(0.35)
        }
        .animation(.easeInOut(duration: 0.8), value: game?.id)
    }
}

private struct Sidebar: View {
    let library: LibraryModel
    @Namespace private var selection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Library")
                .font(.system(size: 22, weight: .heavy).width(.condensed))
                .padding(.horizontal, 14)
                .padding(.top, 52)
                .padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(library.games) { game in
                        GameRow(game: game, selected: game.id == library.selectedID, namespace: selection)
                            .onTapGesture { withAnimation(Motion.switchGame) { library.selectedID = game.id } }
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .background(.ultraThinMaterial.opacity(0.7))
        .overlay(alignment: .trailing) { Rectangle().fill(.white.opacity(0.06)).frame(width: 1) }
    }
}

private struct GameRow: View {
    let game: GameModel
    let selected: Bool
    let namespace: Namespace.ID
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ArtImage(url: game.profile.artwork.portrait)
                .frame(width: 40, height: 60)
                .background(game.profile.accent.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(game.profile.title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    StatusDot(state: game.state, accent: game.profile.accent)
                    Text(game.busy ? (game.step?.title ?? "Working…") : game.state.shortSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .animation(Motion.morph, value: game.state)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 10)
                    .fill(game.profile.accent.opacity(0.22))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(game.profile.accent.opacity(0.45), lineWidth: 1))
                    .matchedGeometryEffect(id: "selection", in: namespace)
            } else if hovering {
                RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.06))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { over in withAnimation(.easeOut(duration: 0.15)) { hovering = over } }
        .contextMenu {
            Button(game.state.actionTitle, action: game.primaryAction).disabled(game.busy)
            Button("Open Steam", action: game.openSteam).disabled(!game.steamAvailable || game.busy)
            Divider()
            Button("Show logs", action: game.showLogs)
        }
    }
}

/// Green when ready, pulsing in the game's color while it plays.
struct StatusDot: View {
    let state: GameState
    let accent: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var color: Color {
        switch state {
        case .ready: .green
        case .running: accent
        case .installing: .blue
        default: .secondary
        }
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .overlay {
                if state == .running && !reduceMotion {
                    Circle().stroke(color, lineWidth: 1.5)
                        .phaseAnimator([false, true]) { ring, expanded in
                            ring.scaleEffect(expanded ? 2.6 : 1).opacity(expanded ? 0 : 0.8)
                        } animation: { expanded in expanded ? .easeOut(duration: 1.4) : .linear(duration: 0) }
                }
            }
            .animation(Motion.morph, value: state)
    }
}
