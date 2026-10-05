import MacGamesCore
import SwiftUI

struct GameDetailView: View {
    @Bindable var game: GameModel
    @State private var logoIn = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                hero.frame(height: max(300, geo.size.height * 0.54))
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xxl) {
                        ActionBar(game: game)
                        if let error = game.error {
                            ErrorBanner(message: error, showLogs: game.showLogs, dismiss: game.dismissError)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if game.showsSetupSteps {
                            SetupStepsView(game: game)
                                .transition(.opacity.combined(with: .offset(y: 10)))
                        }
                        SettingsSection(game: game)
                    }
                    .padding(.horizontal, Space.page)
                    .padding(.top, Space.xl)
                    .padding(.bottom, Space.xxl + Space.l)
                    .frame(maxWidth: 760 + 2 * Space.page, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .animation(Motion.morph, value: game.error)
                    .animation(Motion.morph, value: game.showsSetupSteps)
                }
                .scrollIndicators(.never)
            }
        }
        .confirmationDialog("Stop \(game.profile.title)?", isPresented: $game.confirmingStop) {
            Button("Stop the game and Steam", role: .destructive, action: game.stop)
        } message: {
            Text("The game and Steam close at once. Progress since your last save is lost.")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // The art dissolves into the window's backdrop instead of ending at an edge.
            ArtImage(url: game.profile.artwork.hero, focus: game.profile.heroFocus, drift: true)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.55), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            ArtFit(url: game.profile.artwork.logo)
                .frame(maxWidth: 360, maxHeight: 150, alignment: .bottomLeading)
                .shadow(color: .black.opacity(0.6), radius: 18, y: 6)
                .padding(.leading, Space.page - 12)
                .padding(.bottom, Space.l)
                .opacity(logoIn ? 1 : 0)
                .offset(y: logoIn || reduceMotion ? 0 : 22)
                .accessibilityLabel(game.profile.title)
        }
        .clipped()
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.12)) { logoIn = true } }
    }
}

private struct ActionBar: View {
    let game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Button(action: game.primaryAction) {
                HStack(spacing: Space.s) {
                    if game.busy {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: game.state.actionSymbol)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    Text(game.state.actionTitle).contentTransition(.interpolate)
                }
                .font(.system(size: 16, weight: .bold))
                .padding(.horizontal, Space.xl + Space.xs)
                .frame(minWidth: 140)
                .frame(height: 44)
                .background(Capsule().fill(game.state == .running ? Color.white.opacity(0.16) : game.profile.accent))
                .foregroundStyle(game.state == .running ? Color.white : game.profile.onAccent)
                .contentShape(Capsule())
            }
            .buttonStyle(PressableStyle())
            .disabled(game.locked)
            .keyboardShortcut(.defaultAction)
            .animation(Motion.morph, value: game.state)
            .animation(Motion.morph, value: game.busy)

            Text(game.activity ?? game.state.summary)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
                .contentTransition(.opacity)
                .padding(.leading, Space.xs)
                .animation(Motion.morph, value: game.activity)

            if game.state == .installing, let progress = game.downloadProgress {
                DownloadBar(progress: progress, accent: game.profile.accent)
                    .frame(maxWidth: 420)
                    .padding(.leading, Space.xs)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Motion.morph, value: game.state)
    }
}

/// A thin bar with the percentage, animated as Steam reports bytes.
struct DownloadBar: View {
    let progress: Double
    let accent: Color

    var body: some View {
        HStack(spacing: Space.s) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.12))
                    Capsule().fill(accent).frame(width: max(4, geo.size.width * progress))
                }
            }
            .frame(height: 5)
            Text(progress, format: .percent.precision(.fractionLength(0)))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .contentTransition(.numericText(value: progress))
        }
        .animation(.easeOut(duration: 0.6), value: progress)
    }
}

/// Buttons sink slightly while pressed and dim when disabled.
struct PressableStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private struct ErrorBanner: View {
    let message: String
    let showLogs: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.m) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12))
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Show logs", action: showLogs).buttonStyle(.link)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(.secondary)
        }
        .padding(Space.l)
        .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.35)))
    }
}

private struct SettingsSection: View {
    @Bindable var game: GameModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Settings").font(.system(size: 15, weight: .semibold))
            VStack(spacing: 0) {
                row("Performance HUD", detail: "Shows the Metal frame rate overlay in the game.") {
                    Toggle("", isOn: $game.settings.hud).labelsHidden().toggleStyle(.switch)
                }
                if game.profile.optimizedExecutableSHA256 != nil {
                    Divider().opacity(0.3)
                    row("x87 optimization", detail: "Faster math through x87sidecar. It turns itself off for game builds it does not know.") {
                        Toggle("", isOn: $game.settings.optimized).labelsHidden().toggleStyle(.switch)
                    }
                }
                if game.profile.graphics == .dxmt {
                    Divider().opacity(0.3)
                    row("Window size", detail: "Sets a borderless window that fits this display on the next launch.") {
                        Button("Reset", action: game.resetDisplay)
                    }
                }
                Divider().opacity(0.3)
                row("Game files", detail: game.dataFolder.path) {
                    HStack {
                        Button("Logs", action: game.showLogs)
                        Button("Show in Finder", action: game.showData)
                    }
                }
            }
            .padding(.horizontal, Space.l + Space.xs)
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
            Text("Setting changes apply the next time Steam starts for this game.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, Space.xs)
        }
        .disabled(game.locked)
    }

    private func row<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.vertical, Space.m + 2)
    }
}
