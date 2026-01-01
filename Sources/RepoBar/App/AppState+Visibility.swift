import Foundation
import RepoBarCore

extension AppState {
    func localMatchRepoNamesForLocalProjects(repos: [Repository], includePinned: Bool) -> Set<String> {
        var names = Set(repos.map(\.name))
        guard includePinned else { return names }
        let pinned = self.session.settings.repoList.pinnedRepositories
        for fullName in pinned {
            if let last = fullName.split(separator: "/").last {
                names.insert(String(last))
            }
        }
        return names
    }

    func applyVisibilityFilters(to repos: [Repository]) -> [Repository] {
        let options = AppState.VisibleSelectionOptions(
            pinned: self.session.settings.repoList.pinnedRepositories,
            hidden: Set(self.session.settings.repoList.hiddenRepositories),
            includeForks: self.session.settings.repoList.showForks,
            includeArchived: self.session.settings.repoList.showArchived,
            limit: Int.max,
            ownerFilter: self.session.settings.repoList.ownerFilter
        )
        return AppState.selectVisible(all: repos, options: options)
    }

    func selectMenuTargets(from repos: [Repository]) -> [Repository] {
        RepositoryPipeline.apply(repos, query: self.menuQuery())
    }

    private func menuQuery() -> RepositoryQuery {
        let selection = self.session.menuRepoSelection
        let settings = self.session.settings
        let scope: RepositoryScope = selection.isPinnedScope ? .pinned : .all
        let ageCutoff = RepositoryQueryDefaults.ageCutoff(
            scope: scope,
            ageDays: RepositoryQueryDefaults.defaultAgeDays
        )
        return RepositoryQuery(
            scope: scope,
            onlyWith: selection.onlyWith,
            includeForks: settings.repoList.showForks,
            includeArchived: settings.repoList.showArchived,
            sortKey: settings.repoList.menuSortKey,
            limit: settings.repoList.displayLimit,
            ageCutoff: ageCutoff,
            pinned: settings.repoList.pinnedRepositories,
            hidden: Set(settings.repoList.hiddenRepositories),
            pinPriority: true,
            ownerFilter: settings.repoList.ownerFilter
        )
    }

    func applyPinnedOrder(to repos: [Repository]) -> [Repository] {
        let pinned = self.session.settings.repoList.pinnedRepositories
        return repos.map { repo in
            if let idx = pinned.firstIndex(of: repo.fullName) {
                return repo.withOrder(idx)
            }
            return repo
        }
    }

    func addPinned(_ fullName: String) async {
        guard !self.session.settings.repoList.pinnedRepositories.contains(fullName) else { return }
        self.session.settings.repoList.pinnedRepositories.append(fullName)
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func removePinned(_ fullName: String) async {
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    func hide(_ fullName: String) async {
        guard !self.session.settings.repoList.hiddenRepositories.contains(fullName) else { return }
        self.session.settings.repoList.hiddenRepositories.append(fullName)
        // If hidden, also unpin to avoid stale pin list.
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        self.session.repositories.removeAll { $0.fullName == fullName }
        await self.refresh()
    }

    func unhide(_ fullName: String) async {
        self.session.settings.repoList.hiddenRepositories.removeAll { $0 == fullName }
        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    /// Sets a repository's visibility in one place, keeping pinned/hidden arrays consistent.
    func setVisibility(for fullName: String, to visibility: RepoVisibility) async {
        // Always trim first to avoid storing whitespace variants.
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Remove from both buckets before re-adding.
        self.session.settings.repoList.pinnedRepositories.removeAll { $0 == trimmed }
        self.session.settings.repoList.hiddenRepositories.removeAll { $0 == trimmed }

        switch visibility {
        case .pinned:
            self.session.settings.repoList.pinnedRepositories.append(trimmed)
        case .hidden:
            self.session.settings.repoList.hiddenRepositories.append(trimmed)
        case .visible:
            break
        }

        self.settingsStore.save(self.session.settings)
        await self.refresh()
    }

    struct VisibleSelectionOptions {
        let pinned: [String]
        let hidden: Set<String>
        let includeForks: Bool
        let includeArchived: Bool
        let limit: Int
        let ownerFilter: [String]
    }

    nonisolated static func selectVisible(all repos: [Repository], options: VisibleSelectionOptions) -> [Repository] {
        let pinnedSet = Set(options.pinned)
        let filtered = repos.filter { !options.hidden.contains($0.fullName) }
        let visible = RepositoryFilter.apply(
            filtered,
            includeForks: options.includeForks,
            includeArchived: options.includeArchived,
            pinned: pinnedSet,
            ownerFilter: options.ownerFilter
        )
        let limited = Array(visible.prefix(max(options.limit, 0)))
        return limited.sorted { lhs, rhs in
            switch (options.pinned.firstIndex(of: lhs.fullName), options.pinned.firstIndex(of: rhs.fullName)) {
            case let (l?, r?): l < r
            case (.some, .none): true
            case (.none, .some): false
            default: false
            }
        }
    }
}
