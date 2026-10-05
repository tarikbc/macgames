import MacGamesCore
import SwiftUI

struct GameDetailView: View {
    @Bindable var game: GameModel
    @State private var logoIn = false
    /// How far the page has scrolled; negative while pulled past the top.
    @State private var scrolled: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Height of the header once the art has collapsed.
    static let collapsedHeight: CGFloat = 76

    var body: some View {
        GeometryReader { geo in
            let expanded = max(300, geo.size.height * 0.54)
            // On a wide window the page is a centered column; the logo and the header button line up with it.
            let inset = max(0, (geo.size.width - Space.column - 2 * Space.page) / 2)
            let range = expanded - Self.collapsedHeight
            // 0 with the full art, 1 once it has collapsed into the header.
            let collapse = min(1, max(0, scrolled / range))
            // The small Play button appears once the page's own button has gone under the bar.
            let mainButtonHidden = scrolled > expanded + Space.xl + 44 - Self.collapsedHeight
            ZStack(alignment: .top) {
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
                    .padding(.top, expanded + Space.xl)
                    .padding(.bottom, Space.xxl + Space.l)
                    .frame(maxWidth: Space.column + 2 * Space.page, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    // Even a short page can scroll the art and the main button under the bar.
                    .frame(minHeight: geo.size.height + expanded, alignment: .top)
                    .animation(Motion.morph, value: game.error)
                    .animation(Motion.morph, value: game.showsSetupSteps)
                }
                .scrollIndicators(.never)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
                    scrolled = offset
                }

                // Shrinks from the full art to a slim header as the page scrolls, and
                // stretches a little when pulled down past the top.
                hero(collapse: collapse, inset: inset)
                    .frame(height: max(Self.collapsedHeight, expanded - scrolled))
                    .allowsHitTesting(false)
                    .overlay(alignment: .trailing) {
                        CompactPlay(game: game)
                            .padding(.trailing, inset + Space.page)
                            .opacity(mainButtonHidden ? 1 : 0)
                            .offset(x: mainButtonHidden || reduceMotion ? 0 : 12)
                            .allowsHitTesting(mainButtonHidden)
                            .animation(Motion.morph, value: mainButtonHidden)
                    }
            }
        }
        .confirmationDialog("Stop \(game.profile.title)?", isPresented: $game.confirmingStop) {
            Button("Stop the game and Steam", role: .destructive, action: game.stop)
        } message: {
            Text("The game and Steam close at once. Progress since your last save is lost.")
        }
        .confirmationDialog(removalTitle, isPresented: removalShown, presenting: game.removal) { removal in
            switch removal {
            case .uninstall: Button("Uninstall", role: .destructive, action: game.confirmRemoval)
            case .removeSetup: Button("Remove setup", role: .destructive, action: game.confirmRemoval)
            }
        } message: { removal in
            Text(removalMessage(removal))
        }
    }

    private var removalShown: Binding<Bool> {
        Binding(get: { game.removal != nil }, set: { if !$0 { game.removal = nil } })
    }

    private var removalTitle: String {
        switch game.removal {
        case .removeSetup: "Remove the \(game.profile.gameEnvironment.title) setup?"
        default: "Uninstall \(game.profile.title)?"
        }
    }

    private func removalMessage(_ removal: GameModel.Removal) -> String {
        switch removal {
        case .uninstall(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return game.launcherName == "Steam"
                ? "MacGames deletes the game's files (\(size)). Your saves, settings and Steam account stay. Steam closes first."
                : "Blizzard's uninstaller opens to delete the game's files (\(size)). Your saves and Battle.net account stay."
        case .removeSetup(let bytes):
            let size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
            return "MacGames deletes \(game.launcherName), its sign-in and the Windows files of \(game.profile.gameEnvironment.title) (\(size)). "
                + "Saves kept only in those files go too. You can set it up again later."
        }
    }

    private func hero(collapse: CGFloat, inset: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Expanded, the art dissolves into the window's backdrop. Collapsed, it turns
            // into a frosted bar in the game's own colors with a crisp bottom edge.
            ArtImage(url: game.profile.art?.hero, focus: game.profile.heroFocus, drift: true)
                .blur(radius: 24 * collapse)
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.55 + 0.45 * collapse),
                                             .init(color: .black.opacity(collapse), location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            Rectangle().fill(.ultraThinMaterial).opacity(collapse)
            Rectangle().fill(.black.opacity(0.35 * collapse))
            ArtFit(url: game.profile.art?.logo, fallback: game.profile.title)
                // Logo PNGs carry wide transparent margins, so the collapsed size stays generous.
                .frame(maxWidth: 360 - 150 * collapse, maxHeight: 150 - 94 * collapse, alignment: .bottomLeading)
                .shadow(color: .black.opacity(0.6 - 0.25 * collapse), radius: 18 - 12 * collapse, y: 6 - 5 * collapse)
                .padding(.leading, inset + Space.page - 12)
                .padding(.bottom, Space.l - 6 * collapse)
                .opacity(logoIn ? 1 : 0)
                .offset(y: logoIn || reduceMotion ? 0 : 22)
                .accessibilityLabel(game.profile.title)
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(.white.opacity(0.1)).frame(height: 1).opacity(collapse)
        }
        .clipped()
        .shadow(color: .black.opacity(0.35 * collapse), radius: 14, y: 6)
        .onAppear { withAnimation(.spring(duration: 0.7, bounce: 0.2).delay(0.12)) { logoIn = true } }
    }
}

/// The main action in a small size, shown in the collapsed header.
private struct CompactPlay: View {
    let game: GameModel

    var body: some View {
        Button(action: game.primaryAction) {
            HStack(spacing: 6) {
                Image(systemName: game.state.actionSymbol).contentTransition(.symbolEffect(.replace))
                Text(game.state.actionTitle(launcher: game.launcherName))
            }
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, Space.l)
            .frame(height: 32)
            .background(Capsule().fill(game.state == .running ? Color.white.opacity(0.16) : game.profile.accent))
            .foregroundStyle(game.state == .running ? Color.white : game.profile.onAccent)
            .contentShape(Capsule())
        }
        .buttonStyle(PressableStyle())
        .disabled(game.locked)
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
                    Text(game.state.actionTitle(launcher: game.launcherName)).contentTransition(.interpolate)
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
            .overlay(alignment: .trailing) {
                if game.profile.online != nil, game.state == .ready {
                    Button(action: game.playOnline) {
                        Label(game.onlineReady ? "Play Online" : "Set up online", systemImage: "globe")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.horizontal, Space.l + Space.xs)
                            .frame(height: 44)
                            .background(Capsule().fill(.white.opacity(0.12)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(PressableStyle())
                    .disabled(game.locked)
                    .fixedSize()
                    .alignmentGuide(.trailing) { $0[.leading] - Space.m }
                    .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }

            Text(game.activity ?? game.state.summary(launcher: game.launcherName))
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
                    row("x87 optimization", detail: game.optimization.detail) {
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
                row("Game files", detail: (game.dataFolder.path as NSString).abbreviatingWithTildeInPath) {
                    HStack {
                        Button("Logs", action: game.showLogs)
                        Button("Show in Finder", action: game.showData)
                    }
                }
            }
            .modifier(Card())
            Text("Setting changes apply the next time \(game.launcherName) starts for this game.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.leading, Space.xs)
            if game.canUninstall {
                row("Uninstall", detail: "Deletes the game's files from this Mac. Saves and settings stay.") {
                    Button("Uninstall…", role: .destructive, action: game.requestUninstall)
                }
                .modifier(Card())
                .padding(.top, Space.s)
            } else if game.canRemoveSetup {
                row("Remove setup", detail: "Deletes \(game.launcherName) and the Windows files of \(game.profile.gameEnvironment.title).") {
                    Button("Remove…", role: .destructive, action: game.requestRemoveSetup)
                }
                .modifier(Card())
                .padding(.top, Space.s)
            }
        }
        .disabled(game.locked)
    }

    private struct Card: ViewModifier {
        func body(content: Content) -> some View {
            content
                .padding(.horizontal, Space.l + Space.xs)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.08)))
        }
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
