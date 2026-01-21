# Changelog

## 0.2.0 - 2026-01-21

- macOS: add “Show only my repositories” toggle (owner filter) for repo lists and search.
- macOS: fix the toggle to reset to “show all” when disabled; disable it when signed out.
- macOS: fix commit links to respect GitHub Enterprise host (#9).
- macOS: add GitHub.com vs Enterprise login picker with OAuth help text (#4).
- macOS: show OAuth errors in Accounts sign-in UI (#6).
- macOS: add token status checks + forced refresh buttons in Settings for debugging auth issues.
- macOS: prevent token check/refresh from hanging; add timeouts and diagnostics logging.
- macOS: detect auth failures (401/refresh errors) and log out cleanly with a clearer message.
- macOS: preserve keychain access groups in signed builds so app + CLI share tokens (#16, thanks @jj3ny).
- macOS: keep the menu open after pin/unpin/hide/move actions (#25, thanks @bahag-chaurasiak).
- macOS: make Local Projects scan depth configurable (default 4) (#11, thanks @shunkakinoki).
- macOS: allow importing GitHub CLI tokens with host matching and no refresh loop (#24, thanks @bahag-chaurasiak).
- macOS: stabilize repo settings autocomplete (no spinner layout wiggle), widen the dropdown, show repo stats/badges, fix filtering/hover/scroll, and anchor/size the dropdown to results (no bounce on shrink).
- macOS: widen Enterprise Base URL field and shrink auth progress indicators to avoid layout jumps.
- iOS: update app icon + logo assets.
- macOS: derive activity commit links from repo URL when event repo name is missing or malformed.
- macOS: surface a clear error when the OAuth loopback port is already in use (#17, thanks @kiranjd).

## 0.1.2 - 2025-12-31

- iOS app preview (not finished, not in the App Store yet): repo list/cards, activity feed, detail drill‑downs, login/settings, icons/branding, and continued auth/UI polish.
- CLI parity expansion: new repo list subcommands (releases, CI runs, discussions, tags, branches, contributors, commits, activity) plus `--owner/--mine` filters.
- CLI local actions + settings: sync/rebase/reset/checkout, branch/worktree listings, Finder/Terminal open; pin/hide and settings show/set; installer for `repobar`.
- Changelog UX: submenu preview improvements plus Markdown rendering upgrades (block layout, scrollable preview, header alignment).
- Changelog UX: show the first released section headline in the submenu badge (skips Unreleased).
- Changelog UX: prefetch on repo submenu open and refresh the badge after load.
- Changelog UX: switch to Swift Markdown AST parsing for cross-platform block rendering.
- Releases submenu: show latest release name next to the count badge.
- Menu customization: Display settings to reorder/hide main menu and repo submenu items (reset to defaults), with spacing tweaks.
- Logging/diagnostics: swift-log integration with OSLog + optional file logging; debug logging settings for macOS/iOS.
- Reliability: menu rehydrate on attach, invalidate empty menu cache, stabilize contribution header heatmap size, limit “More” submenus to 20 entries.
- Repo access + errors: include org/collaborator repos, improve repo detail error messaging, cache discussions capability and hide disabled entries.

## 0.1.1 - 2025-12-31

- Add repo submenu changelog preview (CHANGELOG.md or CHANGELOG) with inline markdown rendering.
- Changelog submenu: move under Open in GitHub, make preview scrollable, and show entry counts since last release.
- Improve menu loading UX (repo loading row, earlier contribution fetch) and restore markdown formatting in changelog preview.
- Fix settings login to use default GitHub credentials when blank, refresh after sign-in, and avoid stuck state.
- Dev: SwiftLint cleanup in changelog loader.
- iOS: fix light/dark glass styling and switch to a full-screen login layout.
- iOS: use the modern `UILaunchScreen` plist entry to avoid letterboxed launch.
- iOS: add a close button to the Settings sheet.
- iOS: switch GitHub auth callback to `https://repobar.app/oauth-callback`.
- Site: add Apple App Site Association for `repobar.app` universal links.
- iOS: add `webcredentials` associated domain for HTTPS auth callbacks.
- iOS: silence AppIntents metadata build warnings.
- iOS: add the RepoBar logo to the login screen and app icon.
- iOS: present the logo in a squircle with more padding on login.
- iOS: add activity/commit icons in the activity list.
- iOS: add a repo detail hierarchy with category drill-down lists.
- iOS: declare iPad orientations to silence Xcode build warnings.
- iOS: show avatars in activity and repo detail lists.
- iOS: soften the glass background to match native palettes.
- iOS: keep file browser navigation within the repo detail stack.
- iOS: improve repo detail error messaging and logging.
- Fix CLI: allow invoking bundled `repobarcli` directly (argv0 normalization).
- Fix CLI auth refresh: show actionable error when refresh response is missing tokens.
- CLI: add markdown rendering command backed by Swiftdansi.
- CLI: add changelog parser command and end-to-end markdown/changelog tests.
- CLI: default changelog command to CHANGELOG files in the repo when no path is provided.
- Add Settings installer to link `repobar` CLI into common Homebrew paths.
- Add Display settings to reorder/hide main menu and repo submenu items (reset to defaults included).
- Make Display reset action destructive and stabilize spacing for rows without subtitles.
- Invalidate menu cache and rebuild if the menu appears too small when opening.
- Add padding between About links and bump settings window height for more breathing room.
- Increase padding between Display list entries.
- Remove pinned repo move up/down commands from repo submenu.
- Limit "More Activity/Commits" submenus to 20 entries.
- Include organization and collaborator repositories in repo lists.
- CLI: add `--owner`/`--mine` filters for repos list.

## 0.1.0 - 2025-12-31

First public release of RepoBar — a macOS menubar dashboard for GitHub repo health, activity, and local project state.

### Highlights
- Live repository cards with CI status, activity, releases, and rate‑limit awareness.
- Rich submenus for recent pull requests, issues, releases, workflow runs, discussions, tags, branches, and commits.
- Local Git state surfaced directly in the menu (branch, upstream/ahead/behind, dirty files, worktrees) with safe actions.
- Contribution heatmap header and global activity feed.
- Fast, native menu UI with adaptive layout and caching for performance.

### Feature overview
- **Menubar experience**
  - Repository cards with stats (stars, forks, issues, last push), CI badge, activity preview, and optional heatmaps.
  - Pinned/hidden repos, menu filters, and configurable sorting.
  - Empty/logged‑out states that explain what to do next.

- **Recent activity & insights**
  - Pull requests, issues, releases, workflow runs, discussions, tags, branches, and commit lists per repo.
  - Global activity menu with recent events and commits.
  - Activity links deep‑link to the most relevant GitHub pages.

- **Local projects & Git actions**
  - Local repo status: current branch, upstream sync, dirty counts, and file lists.
  - Worktree and branch menus with metadata and quick actions.
  - Open in Finder/Terminal, checkout, create branch/worktree, sync/rebase/reset.

- **Auth & API**
  - OAuth login, secure token refresh, and shared core used by the CLI.
  - Rate‑limit awareness and caching to minimize GitHub API usage.

- **Contribution heatmap**
  - Header heatmap (cached) with the ability to refresh and clear cache.
  - Optional menu heatmaps aligned to a week‑based date range.

- **Performance & reliability**
  - Cached repo details, activity, and heatmaps for a snappy menu.
  - Menu layout caching, reuse of menu items, and debounced refresh.
  - Timeouts and graceful fallback for slow network requests.

- **CLI** (`repobar`)
  - Status and repo listings with filters, JSON/plain output, and release info.
  - Commands for issues/pulls lists, pinned/hidden scopes, and activity age filtering.

- **Updates**
  - Sparkle updater for signed builds with update‑ready menu entry and full dialog flow.

- **Developer tooling**
  - SwiftPM + pnpm scripts, lint/format, Apollo GraphQL codegen.
