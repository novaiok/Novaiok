import Foundation
import RepoBarCore

@MainActor
final class RecentMenuService {
    let listLimit: Int
    let previewLimit: Int
    let cacheTTL: TimeInterval
    let loadTimeout: TimeInterval

    private let github: GitHubClient
    private let recentIssuesCache = RecentListCache<RepoIssueSummary>()
    private let recentPullRequestsCache = RecentListCache<RepoPullRequestSummary>()
    private let recentReleasesCache = RecentListCache<RepoReleaseSummary>()
    private let recentWorkflowRunsCache = RecentListCache<RepoWorkflowRunSummary>()
    private let recentCommitsCache = RecentListCache<RepoCommitSummary>()
    private let recentDiscussionsCache = RecentListCache<RepoDiscussionSummary>()
    private let recentTagsCache = RecentListCache<RepoTagSummary>()
    private let recentBranchesCache = RecentListCache<RepoBranchSummary>()
    private let recentContributorsCache = RecentListCache<RepoContributorSummary>()
    private var recentCommitCounts: [String: Int] = [:]

    init(
        github: GitHubClient,
        listLimit: Int = AppLimits.RecentLists.limit,
        previewLimit: Int = AppLimits.RecentLists.previewLimit,
        cacheTTL: TimeInterval = AppLimits.RecentLists.cacheTTL,
        loadTimeout: TimeInterval = AppLimits.RecentLists.loadTimeout
    ) {
        self.github = github
        self.listLimit = listLimit
        self.previewLimit = previewLimit
        self.cacheTTL = cacheTTL
        self.loadTimeout = loadTimeout
    }

    func descriptor(for kind: RepoRecentMenuKind) -> RecentMenuDescriptor? {
        self.descriptors()[kind]
    }

    func descriptors() -> [RepoRecentMenuKind: RecentMenuDescriptor] {
        let commitDescriptor = self.commitDescriptor()

        let descriptors: [RecentMenuDescriptor] = [
            commitDescriptor,
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .issues,
                headerTitle: "Open Issues",
                headerIcon: "exclamationmark.circle",
                emptyTitle: "No open issues",
                cache: self.recentIssuesCache,
                wrap: RecentMenuItems.issues,
                unwrap: { boxed in
                    if case let .issues(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentIssues(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .pullRequests,
                headerTitle: "Open Pull Requests",
                headerIcon: "arrow.triangle.branch",
                emptyTitle: "No open pull requests",
                cache: self.recentPullRequestsCache,
                wrap: RecentMenuItems.pullRequests,
                unwrap: { boxed in
                    if case let .pullRequests(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentPullRequests(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .releases,
                headerTitle: "Open Releases",
                headerIcon: "tag",
                emptyTitle: "No releases",
                cache: self.recentReleasesCache,
                wrap: RecentMenuItems.releases,
                unwrap: { boxed in
                    if case let .releases(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentReleases(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .ciRuns,
                headerTitle: "Open Actions",
                headerIcon: "bolt",
                emptyTitle: "No CI runs",
                cache: self.recentWorkflowRunsCache,
                wrap: RecentMenuItems.workflowRuns,
                unwrap: { boxed in
                    if case let .workflowRuns(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentWorkflowRuns(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .discussions,
                headerTitle: "Open Discussions",
                headerIcon: "bubble.left.and.bubble.right",
                emptyTitle: "No discussions",
                cache: self.recentDiscussionsCache,
                wrap: RecentMenuItems.discussions,
                unwrap: { boxed in
                    if case let .discussions(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentDiscussions(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .tags,
                headerTitle: "Open Tags",
                headerIcon: "tag",
                emptyTitle: "No tags",
                cache: self.recentTagsCache,
                wrap: RecentMenuItems.tags,
                unwrap: { boxed in
                    if case let .tags(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentTags(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .branches,
                headerTitle: "Open Branches",
                headerIcon: "point.topleft.down.curvedto.point.bottomright.up",
                emptyTitle: "No branches",
                cache: self.recentBranchesCache,
                wrap: RecentMenuItems.branches,
                unwrap: { boxed in
                    if case let .branches(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.recentBranches(owner: owner, name: name, limit: limit)
                }
            )),
            self.makeDescriptor(RecentMenuDescriptorConfig(
                kind: .contributors,
                headerTitle: "Open Contributors",
                headerIcon: "person.2",
                emptyTitle: "No contributors",
                cache: self.recentContributorsCache,
                wrap: RecentMenuItems.contributors,
                unwrap: { boxed in
                    if case let .contributors(items) = boxed { return items }
                    return nil
                },
                fetch: { github, owner, name, limit in
                    try await github.topContributors(owner: owner, name: name, limit: limit)
                }
            ))
        ]

        return Dictionary(uniqueKeysWithValues: descriptors.map { ($0.kind, $0) })
    }

    func cachedRecentListCount(fullName: String, kind: RepoRecentMenuKind) -> Int? {
        guard let descriptor = self.descriptor(for: kind) else { return nil }
        return descriptor.stale(fullName)?.count
    }

    func cachedRecentCommitCount(fullName: String) -> Int? {
        if let total = self.recentCommitCounts[fullName] { return total }
        return self.recentCommitsCache.stale(for: fullName)?.count
    }

    func cachedCommits(fullName: String, now: Date = Date()) -> [RepoCommitSummary]? {
        self.recentCommitsCache.cached(for: fullName, now: now, maxAge: self.cacheTTL)
            ?? self.recentCommitsCache.stale(for: fullName)
    }

    func cachedCommitDigest(fullName: String) -> Int? {
        let now = Date()
        guard let commits = self.cachedCommits(fullName: fullName, now: now), commits.isEmpty == false else { return nil }
        var hasher = Hasher()
        for commit in commits {
            hasher.combine(commit.sha)
            hasher.combine(commit.authoredAt.timeIntervalSinceReferenceDate)
        }
        return hasher.finalize()
    }

    /// Clears all in-memory caches to free memory.
    func clearAllCaches() {
        self.recentIssuesCache.clear()
        self.recentPullRequestsCache.clear()
        self.recentReleasesCache.clear()
        self.recentWorkflowRunsCache.clear()
        self.recentCommitsCache.clear()
        self.recentDiscussionsCache.clear()
        self.recentTagsCache.clear()
        self.recentBranchesCache.clear()
        self.recentContributorsCache.clear()
        self.recentCommitCounts.removeAll()
    }

    private func commitDescriptor() -> RecentMenuDescriptor {
        RecentMenuDescriptor(
            kind: .commits,
            headerTitle: "Open Commits",
            headerIcon: "arrow.turn.down.right",
            emptyTitle: "No commits",
            cached: { key, now, ttl in
                self.recentCommitsCache.cached(for: key, now: now, maxAge: ttl).map(RecentMenuItems.commits)
            },
            stale: { key in
                self.recentCommitsCache.stale(for: key).map(RecentMenuItems.commits)
            },
            needsRefresh: { key, now, ttl in
                self.recentCommitsCache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, owner, name, limit in
                let task = self.recentCommitsCache.task(for: key) {
                    let list = try await self.github.recentCommits(owner: owner, name: name, limit: limit)
                    await MainActor.run {
                        self.recentCommitCounts[key] = list.totalCount ?? list.items.count
                    }
                    return list.items
                }
                defer { self.recentCommitsCache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                self.recentCommitsCache.store(items, for: key, fetchedAt: Date())
                return RecentMenuItems.commits(items)
            }
        )
    }

    private func makeDescriptor(
        _ config: RecentMenuDescriptorConfig<some Sendable>
    ) -> RecentMenuDescriptor {
        let fetch = config.fetch

        return RecentMenuDescriptor(
            kind: config.kind,
            headerTitle: config.headerTitle,
            headerIcon: config.headerIcon,
            emptyTitle: config.emptyTitle,
            cached: { key, now, ttl in
                config.cache.cached(for: key, now: now, maxAge: ttl).map(config.wrap)
            },
            stale: { key in
                config.cache.stale(for: key).map(config.wrap)
            },
            needsRefresh: { key, now, ttl in
                config.cache.needsRefresh(for: key, now: now, maxAge: ttl)
            },
            load: { key, owner, name, limit in
                let task = config.cache.task(for: key) {
                    try await fetch(self.github, owner, name, limit)
                }
                defer { config.cache.clearInflight(for: key) }
                let items = try await AsyncTimeout.value(within: self.loadTimeout, task: task)
                config.cache.store(items, for: key, fetchedAt: Date())
                return config.wrap(items)
            }
        )
    }
}

struct RecentMenuDescriptorConfig<Item: Sendable> {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cache: RecentListCache<Item>
    let wrap: ([Item]) -> RecentMenuItems
    let unwrap: (RecentMenuItems) -> [Item]?
    let fetch: @Sendable (GitHubClient, String, String, Int) async throws -> [Item]
}

struct RecentMenuDescriptor {
    let kind: RepoRecentMenuKind
    let headerTitle: String
    let headerIcon: String?
    let emptyTitle: String
    let cached: (String, Date, TimeInterval) -> RecentMenuItems?
    let stale: (String) -> RecentMenuItems?
    let needsRefresh: (String, Date, TimeInterval) -> Bool
    let load: @MainActor (String, String, String, Int) async throws -> RecentMenuItems
}

enum RecentMenuItems: Sendable {
    case commits([RepoCommitSummary])
    case issues([RepoIssueSummary])
    case pullRequests([RepoPullRequestSummary])
    case releases([RepoReleaseSummary])
    case workflowRuns([RepoWorkflowRunSummary])
    case discussions([RepoDiscussionSummary])
    case tags([RepoTagSummary])
    case branches([RepoBranchSummary])
    case contributors([RepoContributorSummary])

    var isEmpty: Bool {
        switch self {
        case let .commits(items): items.isEmpty
        case let .issues(items): items.isEmpty
        case let .pullRequests(items): items.isEmpty
        case let .releases(items): items.isEmpty
        case let .workflowRuns(items): items.isEmpty
        case let .discussions(items): items.isEmpty
        case let .tags(items): items.isEmpty
        case let .branches(items): items.isEmpty
        case let .contributors(items): items.isEmpty
        }
    }

    var count: Int {
        switch self {
        case let .commits(items): items.count
        case let .issues(items): items.count
        case let .pullRequests(items): items.count
        case let .releases(items): items.count
        case let .workflowRuns(items): items.count
        case let .discussions(items): items.count
        case let .tags(items): items.count
        case let .branches(items): items.count
        case let .contributors(items): items.count
        }
    }
}

@MainActor
final class RecentListCache<Item: Sendable> {
    struct Entry {
        var fetchedAt: Date
        var items: [Item]
    }

    /// Maximum number of repository entries to retain per cache type.
    private let maxEntries: Int
    private var entries: [String: Entry] = [:]
    /// Tracks access order for LRU eviction (most recent at end)
    private var accessOrder: [String] = []
    private var inflight: [String: Task<[Item], Error>] = [:]

    init(maxEntries: Int = 50) {
        self.maxEntries = maxEntries
    }

    func cached(for key: String, now: Date, maxAge: TimeInterval) -> [Item]? {
        guard let entry = self.entries[key] else { return nil }
        guard now.timeIntervalSince(entry.fetchedAt) <= maxAge else { return nil }
        // Move to end of access order (most recently used)
        self.touchAccessOrder(key)
        return entry.items
    }

    func stale(for key: String) -> [Item]? {
        self.entries[key]?.items
    }

    func needsRefresh(for key: String, now: Date, maxAge: TimeInterval) -> Bool {
        guard let entry = self.entries[key] else { return true }
        return now.timeIntervalSince(entry.fetchedAt) > maxAge
    }

    func task(for key: String, factory: @escaping @Sendable () async throws -> [Item]) -> Task<[Item], Error> {
        if let existing = self.inflight[key] { return existing }
        let task = Task { try await factory() }
        self.inflight[key] = task
        return task
    }

    func clearInflight(for key: String) {
        self.inflight[key] = nil
    }

    func store(_ items: [Item], for key: String, fetchedAt: Date) {
        let isNewKey = self.entries[key] == nil

        if isNewKey {
            // Only evict when inserting a new key
            while self.entries.count >= self.maxEntries, let oldest = self.accessOrder.first {
                self.accessOrder.removeFirst()
                self.entries.removeValue(forKey: oldest)
            }
            self.accessOrder.append(key)
        } else {
            // Update existing key - move to end of access order
            self.touchAccessOrder(key)
        }

        self.entries[key] = Entry(fetchedAt: fetchedAt, items: items)
    }

    func clear() {
        self.entries.removeAll()
        self.accessOrder.removeAll()
        self.inflight.values.forEach { $0.cancel() }
        self.inflight.removeAll()
    }

    var count: Int {
        self.entries.count
    }

    /// Moves key to end of access order (most recently used)
    private func touchAccessOrder(_ key: String) {
        if let index = self.accessOrder.firstIndex(of: key) {
            self.accessOrder.remove(at: index)
            self.accessOrder.append(key)
        }
    }
}
