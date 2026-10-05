import Foundation

// `MacGames --command <name> --game <id>` runs one step headless and exits.
if CommandLine.arguments.contains("--command") {
    exit(CLI.run(CommandLine.arguments))
}
MacGamesApp.main()
