import CoreGraphics
import Foundation
import MacGamesCore

/// Headless access to every step, for scripting and testing without the UI.
@MainActor
enum CLI {
    static let usage = """
    usage: MacGames --command <check|setup|launcher|install|play|stop|uninstall|remove-setup|status|reset-display|settings>
                    --game <id> [--root <data root>] [--optimized on|off] [--hud on|off]
    games: \(GameProfile.all.map(\.id).joined(separator: ", "))
    """

    static func value(_ name: String, in args: [String]) -> String? {
        guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    static func run(_ args: [String]) -> Int32 {
        guard let command = value("--command", in: args),
              let profile = value("--game", in: args).flatMap(GameProfile.named) else {
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return 64
        }
        let root = value("--root", in: args).map { URL(fileURLWithPath: $0) }
        let game = GameRuntime(profile: profile, root: root, runtime: .inBundle()) { event in
            if case .progress(let line) = event { print(line); fflush(stdout) }
        }
        do {
            switch command {
            case "check":
                let report = try game.check()
                print("Host check passed. Optimization available: \(report.optimizationAvailable)")
                report.notes.forEach { print($0) }
            case "setup":
                try game.prepare()
                try game.installLauncher()
            case "steam", "launcher":
                try game.openLauncher()
            case "install":
                try game.openForInstall()
            case "play":
                try game.play(LaunchContext.mainDisplay())
            case "stop":
                try game.stop()
            case "uninstall":
                try game.uninstall()
            case "remove-setup":
                try game.removeEnvironment()
            case "status":
                print("\(profile.id): \(game.state().rawValue)")
                print("root: \(game.paths.root.path)")
            case "reset-display":
                game.resetDisplay()
                print("The next launch applies the window size again.")
            case "settings":
                var s = game.settings
                if let v = value("--optimized", in: args) { s.optimized = v == "on" }
                if let v = value("--hud", in: args) { s.hud = v == "on" }
                game.settings = s
                print("optimized: \(s.optimized), hud: \(s.hud)")
            default:
                FileHandle.standardError.write(Data((usage + "\n").utf8))
                return 64
            }
            return 0
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            return 1
        }
    }
}
