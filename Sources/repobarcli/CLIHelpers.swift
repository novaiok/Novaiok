import Commander
import Darwin
import Foundation
import RepoBarCore

protocol CommanderRunnableCommand: ParsableCommand {
    static var commandName: String { get }
    mutating func bind(_ values: ParsedValues) throws
}

extension ParsableCommand {
    static func descriptor() -> CommandDescriptor {
        let description = Self.commandDescription
        let instance = Self()
        let signature = CommandSignature.describe(instance).flattened()
        let name = description.commandName ?? String(describing: Self.self).lowercased()
        let subcommands = description.subcommands.map { $0.descriptor() }
        let defaultName = description.defaultSubcommand?.commandDescription.commandName
            ?? description.defaultSubcommand.map { String(describing: $0).lowercased() }
        return CommandDescriptor(
            name: name,
            abstract: description.abstract,
            discussion: description.discussion,
            signature: signature,
            subcommands: subcommands,
            defaultSubcommandName: defaultName
        )
    }
}

extension ParsedValues {
    func flag(_ label: String) -> Bool {
        flags.contains(label)
    }

    func decodeOption<T: ExpressibleFromArgument>(_ label: String) throws -> T? {
        guard let raw = options[label]?.last else { return nil }
        guard let value = T(argument: raw) else {
            throw ValidationError("Invalid value for --\(label): \(raw)")
        }
        return value
    }

    func optionValues(_ label: String) -> [String] {
        options[label] ?? []
    }
}

struct OutputOptions: CommanderParsable, Sendable {
    @Flag(
        names: [.customLong("json"), .customLong("json-output"), .short("j")],
        help: "Output JSON instead of the formatted table"
    )
    var jsonOutput: Bool = false

    @Flag(names: [.customLong("plain")], help: "Plain table output (no links, no colors, no URLs)")
    var plain: Bool = false

    @Flag(names: [.customLong("no-color")], help: "Disable color output")
    var noColor: Bool = false

    init() {}

    mutating func bind(_ values: ParsedValues) {
        self.jsonOutput = values.flag("jsonOutput")
        self.plain = values.flag("plain")
        self.noColor = values.flag("noColor")
    }

    var useColor: Bool {
        self.jsonOutput == false && self.plain == false && self.noColor == false && Ansi.supportsColor
    }
}

extension RepositorySortKey: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "activity", "act", "date":
            self = .activity
        case "issues", "issue", "iss":
            self = .issues
        case "prs", "pr", "pulls", "pull":
            self = .pulls
        case "stars", "star":
            self = .stars
        case "repo", "name":
            self = .name
        case "event", "activity-line", "line":
            self = .event
        default:
            return nil
        }
    }
}

extension GlobalActivityScope: ExpressibleFromArgument {
    public init?(argument: String) {
        switch argument.lowercased() {
        case "all", "all-activity", "allactivity":
            self = .allActivity
        case "my", "mine", "my-activity", "myactivity":
            self = .myActivity
        default:
            return nil
        }
    }
}

enum CLIError: Error {
    case notAuthenticated
    case openFailed
    case unknownCommand(String)

    var message: String {
        switch self {
        case .notAuthenticated:
            "No stored login. Run `repobar login` first."
        case .openFailed:
            "Failed to open the browser."
        case let .unknownCommand(command):
            "Unknown command: \(command)"
        }
    }
}

enum Ansi {
    static let reset = "\u{001B}[0m"
    static let bold = Code("\u{001B}[1m")
    static let red = Code("\u{001B}[31m")
    static let yellow = Code("\u{001B}[33m")
    static let magenta = Code("\u{001B}[35m")
    static let cyan = Code("\u{001B}[36m")
    static let gray = Code("\u{001B}[90m")
    static let oscTerminator = "\u{001B}\\"

    static var supportsColor: Bool {
        guard isatty(fileno(stdout)) != 0 else { return false }
        return ProcessInfo.processInfo.environment["NO_COLOR"] == nil
    }

    static var supportsLinks: Bool {
        isatty(fileno(stdout)) != 0
    }

    struct Code {
        let value: String

        init(_ value: String) {
            self.value = value
        }

        func wrap(_ text: String) -> String {
            "\(self.value)\(text)\(Ansi.reset)"
        }
    }

    static func link(_ label: String, url: URL, enabled: Bool) -> String {
        guard enabled else { return "\(label) \(url.absoluteString)" }
        let start = "\u{001B}]8;;\(url.absoluteString)\(Ansi.oscTerminator)"
        let end = "\u{001B}]8;;\(Ansi.oscTerminator)"
        return "\(start)\(label)\(end)"
    }
}

extension String {
    var singleLine: String {
        let noNewlines = self.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
        return noNewlines.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

func printError(_ message: String) {
    if Ansi.supportsColor {
        print(Ansi.red.wrap("Error: \(message)"))
    } else {
        print("Error: \(message)")
    }
}

func printJSON(_ output: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(output)
    if let json = String(data: data, encoding: .utf8) {
        print(json)
    }
}

func openURL(_ url: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.openFailed }
}

func openPath(_ path: String, application: String? = nil) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    if let application, application.isEmpty == false {
        process.arguments = ["-a", application, path]
    } else {
        process.arguments = [path]
    }
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw CLIError.openFailed }
}

func parseHost(_ raw: String) throws -> URL {
    guard var components = URLComponents(string: raw) else {
        throw ValidationError("Invalid host: \(raw)")
    }
    if components.scheme == nil { components.scheme = "https" }
    guard let url = components.url else {
        throw ValidationError("Invalid host: \(raw)")
    }
    return url
}

enum HelpTarget: String {
    case root
    case repos
    case repo
    case issues
    case pulls
    case releases
    case ci
    case discussions
    case tags
    case branches
    case contributors
    case commits
    case activity
    case local
    case localSync
    case localRebase
    case localReset
    case localBranches
    case worktrees
    case openFinder
    case openTerminal
    case checkout
    case refresh
    case contributions
    case changelog
    case markdown
    case pin
    case unpin
    case hide
    case show
    case settingsShow
    case settingsSet
    case login
    case logout
    case importGHToken
    case status

    static func from(argv: [String]) -> HelpTarget? {
        guard !argv.isEmpty else { return .root }

        if argv.count > 1, argv[1] == "help" {
            let target = argv.dropFirst(2).first
            return HelpTarget.from(token: target)
        }

        guard argv.contains("--help") || argv.contains("-h") else { return nil }
        let target = argv.dropFirst().first(where: { !$0.hasPrefix("-") })
        return HelpTarget.from(token: target)
    }

    private static func from(token: String?) -> HelpTarget {
        guard let token else { return .root }
        switch token {
        case ReposCommand.commandName:
            return .repos
        case RepoCommand.commandName:
            return .repo
        case IssuesCommand.commandName:
            return .issues
        case PullsCommand.commandName:
            return .pulls
        case ReleasesCommand.commandName:
            return .releases
        case CICommand.commandName:
            return .ci
        case DiscussionsCommand.commandName:
            return .discussions
        case TagsCommand.commandName:
            return .tags
        case BranchesCommand.commandName:
            return .branches
        case ContributorsCommand.commandName:
            return .contributors
        case CommitsCommand.commandName:
            return .commits
        case ActivityCommand.commandName:
            return .activity
        case LocalProjectsCommand.commandName:
            return .local
        case LocalSyncCommand.commandName:
            return .localSync
        case LocalRebaseCommand.commandName:
            return .localRebase
        case LocalResetCommand.commandName:
            return .localReset
        case LocalBranchesCommand.commandName:
            return .localBranches
        case WorktreesCommand.commandName:
            return .worktrees
        case OpenFinderCommand.commandName:
            return .openFinder
        case OpenTerminalCommand.commandName:
            return .openTerminal
        case CheckoutCommand.commandName:
            return .checkout
        case RefreshCommand.commandName:
            return .refresh
        case ContributionsCommand.commandName:
            return .contributions
        case ChangelogCommand.commandName:
            return .changelog
        case MarkdownCommand.commandName:
            return .markdown
        case PinCommand.commandName:
            return .pin
        case UnpinCommand.commandName:
            return .unpin
        case HideCommand.commandName:
            return .hide
        case ShowCommand.commandName:
            return .show
        case SettingsShowCommand.commandName:
            return .settingsShow
        case SettingsSetCommand.commandName:
            return .settingsSet
        case LoginCommand.commandName:
            return .login
        case LogoutCommand.commandName:
            return .logout
        case ImportGHTokenCommand.commandName:
            return .importGHToken
        case StatusCommand.commandName:
            return .status
        default:
            return .root
        }
    }
}

func printHelp(_ target: HelpTarget) {
    let text = switch target {
    case .root:
        """
        repobar - list repositories by activity, issues, PRs, stars

        Usage:
          repobar [repos] [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL] [--pinned-only] [--only-with VAL] [--owner LOGIN] [--mine] [--json] [--plain] [--sort KEY]
          repobar repo <owner/name> [--traffic] [--heatmap] [--release] [--json] [--plain]
          repobar issues <owner/name> [--limit N] [--json] [--plain]
          repobar pulls <owner/name> [--limit N] [--json] [--plain]
          repobar releases <owner/name> [--limit N] [--json] [--plain]
          repobar ci <owner/name> [--limit N] [--json] [--plain]
          repobar discussions <owner/name> [--limit N] [--json] [--plain]
          repobar tags <owner/name> [--limit N] [--json] [--plain]
          repobar branches <owner/name> [--limit N] [--json] [--plain]
          repobar contributors <owner/name> [--limit N] [--json] [--plain]
          repobar commits [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]
          repobar activity [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]
          repobar local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]
          repobar local sync <path|owner/name> [--json] [--plain]
          repobar local rebase <path|owner/name> [--json] [--plain]
          repobar local reset <path|owner/name> [--yes] [--json] [--plain]
          repobar local branches <path|owner/name> [--json] [--plain]
          repobar worktrees <path|owner/name> [--json] [--plain]
          repobar open finder <path|owner/name>
          repobar open terminal <path|owner/name>
          repobar checkout <owner/name> [--root PATH] [--destination PATH] [--open] [--json] [--plain]
          repobar refresh [--json] [--plain]
          repobar contributions [--login USER] [--json] [--plain]
          repobar changelog [path] [--release TAG] [--json] [--plain]
          repobar markdown <path> [--width N] [--no-wrap] [--plain] [--no-color]
          repobar pin <owner/name> [--json] [--plain]
          repobar unpin <owner/name> [--json] [--plain]
          repobar hide <owner/name> [--json] [--plain]
          repobar show <owner/name> [--json] [--plain]
          repobar settings show [--json] [--plain]
          repobar settings set <key> <value> [--json] [--plain]
          repobar login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
          repobar logout
          repobar import-gh-token [--host URL]
          repobar status [--json]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --release    Include latest release tag and date
          --event      Show activity event column (hidden by default)
          --forks      Include forked repositories (hidden by default)
          --archived   Include archived repositories (hidden by default)
          --scope      Scope repositories (values: all, pinned, hidden)
          --filter     Filter repositories (values: all, work, issues, prs)
          --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
          --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
          --owner      Only show repositories owned by the given login (repeatable, comma-separated)
          --mine       Only show repositories owned by the authenticated user
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
          -h, --help   Show help
        """
    case .repos:
        """
        repobar repos - list repositories

        Usage:
          repobar repos [--limit N] [--age DAYS] [--release] [--event] [--forks] [--archived] [--scope VAL] [--filter VAL] [--pinned-only] [--only-with VAL] [--owner LOGIN] [--mine] [--json] [--plain] [--sort KEY]

        Options:
          --limit N    Max repositories to fetch (default: all accessible)
          --age DAYS   Only show repos with activity in the last N days (default: 365)
          --release    Include latest release tag and date
          --event      Show activity event column (hidden by default)
          --forks      Include forked repositories (hidden by default)
          --archived   Include archived repositories (hidden by default)
          --scope      Scope repositories (values: all, pinned, hidden)
          --filter     Filter repositories (values: all, work, issues, prs)
          --pinned-only  Only list pinned repositories from settings (alias for --scope pinned)
          --only-with  Only show repos that have issues and/or PRs (values: work, issues, prs)
          --owner      Only show repositories owned by the given login (repeatable, comma-separated)
          --mine       Only show repositories owned by the authenticated user
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --sort KEY   Sort by activity, issues, prs, stars, repo, or event
          --no-color   Disable color output
        """
    case .repo:
        """
        repobar repo - fetch a repository summary

        Usage:
          repobar repo <owner/name> [--traffic] [--heatmap] [--release] [--json] [--plain]

        Options:
          --traffic   Include traffic stats
          --heatmap   Include commit activity heatmap
          --release   Include latest release data
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .issues:
        """
        repobar issues - list open issues

        Usage:
          repobar issues <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max issues to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .pulls:
        """
        repobar pulls - list open pull requests

        Usage:
          repobar pulls <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max PRs to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .releases:
        """
        repobar releases - list recent releases

        Usage:
          repobar releases <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max releases to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .ci:
        """
        repobar ci - list workflow runs

        Usage:
          repobar ci <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max workflow runs to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .discussions:
        """
        repobar discussions - list recent discussions

        Usage:
          repobar discussions <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max discussions to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .tags:
        """
        repobar tags - list recent tags

        Usage:
          repobar tags <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max tags to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .branches:
        """
        repobar branches - list recent branches

        Usage:
          repobar branches <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max branches to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .contributors:
        """
        repobar contributors - list top contributors

        Usage:
          repobar contributors <owner/name> [--limit N] [--json] [--plain]

        Options:
          --limit N   Max contributors to fetch (default: 20)
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .commits:
        """
        repobar commits - list recent commits

        Usage:
          repobar commits [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]

        Options:
          --limit N   Max commits to fetch (default: 20)
          --scope     Activity scope (values: all, my)
          --login     GitHub login for global commits
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .activity:
        """
        repobar activity - list recent activity

        Usage:
          repobar activity [<owner/name>|<login>] [--limit N] [--scope VAL] [--login USER] [--json] [--plain]

        Options:
          --limit N   Max events to fetch (default: 20)
          --scope     Activity scope (values: all, my)
          --login     GitHub login for global activity
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .local:
        """
        repobar local - scan local projects

        Usage:
          repobar local [--root PATH] [--depth N] [--sync] [--limit N] [--json] [--plain]

        Options:
          --root PATH  Project folder to scan (defaults to settings value, then ~/Projects)
          --depth N    Max scan depth (default: 2)
          --sync       Fast-forward pull clean repos that are behind
          --limit N    Limit processed repos (default: all)
          --json       Output JSON instead of formatted table
          --plain      Plain table output (no links, no colors, no URLs)
          --no-color   Disable color output
        """
    case .localSync:
        """
        repobar local sync - sync a local repository

        Usage:
          repobar local sync <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localRebase:
        """
        repobar local rebase - rebase a local repository onto upstream

        Usage:
          repobar local rebase <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localReset:
        """
        repobar local reset - hard reset a local repository to upstream

        Usage:
          repobar local reset <path|owner/name> [--yes] [--json] [--plain]

        Options:
          --yes       Skip confirmation prompt
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .localBranches:
        """
        repobar local branches - list local branches

        Usage:
          repobar local branches <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .worktrees:
        """
        repobar worktrees - list local worktrees

        Usage:
          repobar worktrees <path|owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .openFinder:
        """
        repobar open finder - open a local repository in Finder

        Usage:
          repobar open finder <path|owner/name>
        """
    case .openTerminal:
        """
        repobar open terminal - open a local repository in Terminal

        Usage:
          repobar open terminal <path|owner/name>
        """
    case .checkout:
        """
        repobar checkout - clone a repository into the local projects folder

        Usage:
          repobar checkout <owner/name> [--root PATH] [--destination PATH] [--open] [--json] [--plain]

        Options:
          --root PATH        Root folder to clone into (defaults to Local Projects root)
          --destination PATH Explicit destination folder
          --open             Open Finder after checkout
          --json             Output JSON instead of formatted text
          --plain            Plain output (no links, no colors)
          --no-color         Disable color output
        """
    case .refresh:
        """
        repobar refresh - refresh pinned repositories

        Usage:
          repobar refresh [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .contributions:
        """
        repobar contributions - fetch contribution heatmap

        Usage:
          repobar contributions [--login USER] [--json] [--plain]

        Options:
          --login USER  GitHub login (defaults to current user)
          --json        Output JSON instead of formatted text
          --plain       Plain output (no links, no colors)
          --no-color    Disable color output
        """
    case .changelog:
        """
        repobar changelog - parse a changelog and summarize entries

        Usage:
          repobar changelog [path] [--release TAG] [--json] [--plain]

        Options:
          --release TAG  Release tag to compare against (ex: v1.0.0)
          --json         Output JSON instead of formatted text
          --plain        Plain output (no links, no colors)
          --no-color     Disable color output
        """
    case .markdown:
        """
        repobar markdown - render markdown to ANSI text

        Usage:
          repobar markdown <path> [--width N] [--no-wrap] [--plain] [--no-color]

        Options:
          --width N   Wrap at N columns (defaults to terminal width)
          --no-wrap   Disable line wrapping
          --plain     Plain output (strip ANSI styles)
          --no-color  Disable color output
        """
    case .pin:
        """
        repobar pin - pin a repository

        Usage:
          repobar pin <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .unpin:
        """
        repobar unpin - unpin a repository

        Usage:
          repobar unpin <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .hide:
        """
        repobar hide - hide a repository

        Usage:
          repobar hide <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .show:
        """
        repobar show - show a hidden repository

        Usage:
          repobar show <owner/name> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .settingsShow:
        """
        repobar settings show - show current settings

        Usage:
          repobar settings show [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .settingsSet:
        """
        repobar settings set - update a settings value

        Usage:
          repobar settings set <key> <value> [--json] [--plain]

        Options:
          --json      Output JSON instead of formatted text
          --plain     Plain output (no links, no colors)
          --no-color  Disable color output
        """
    case .login:
        """
        repobar login - sign in via browser OAuth

        Usage:
          repobar login [--host URL] [--client-id ID] [--client-secret SECRET] [--loopback-port PORT]
        """
    case .logout:
        """
        repobar logout - clear stored credentials

        Usage:
          repobar logout
        """
    case .importGHToken:
        """
        repobar import-gh-token - import token from GitHub CLI (gh)

        Usage:
          repobar import-gh-token [--host URL]

        Imports the authentication token from GitHub CLI (gh) into RepoBar.
        This is useful for SSO-enabled organizations where you've already
        authorized the gh CLI but need to use that same access in RepoBar.

        Options:
          --host URL   GitHub host to import from (defaults to current settings)

        Prerequisites:
          - GitHub CLI must be installed (brew install gh)
          - You must be logged in via gh (gh auth login)
          - Your gh token should have SSO authorization for your org
        """
    case .status:
        """
        repobar status - show login state

        Usage:
          repobar status [--json]
        """
    }
    print(text)
}
