import Foundation
import RepoBarCore

actor LocalRepoManager {
    private let notifier = LocalSyncNotifier.shared
    private let discoveryCacheTTL: TimeInterval = AppLimits.LocalRepo.discoveryCacheTTL
    private let statusCacheTTL: TimeInterval = AppLimits.LocalRepo.statusCacheTTL
    private var discoveryCache: [String: DiscoveryCacheEntry] = [:]
    private var statusCache: [String: StatusCacheEntry] = [:]
    private var lastFetchByPath: [String: Date] = [:]

    struct SnapshotResult: Sendable {
        let discoveredCount: Int
        let repoIndex: LocalRepoIndex
        let accessDenied: Bool
    }

    struct SnapshotOptions: Sendable {
        let autoSyncEnabled: Bool
        let fetchInterval: TimeInterval
        let preferredPathsByFullName: [String: String]
        let matchRepoNames: Set<String>
        let forceRescan: Bool
        let maxDepth: Int
    }

    func snapshot(
        rootPath: String?,
        rootBookmarkData: Data?,
        options: SnapshotOptions
    ) async -> SnapshotResult {
        guard let rootPath,
              rootPath.isEmpty == false
        else {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: false)
        }

        let now = Date()

        let fallbackURL = URL(fileURLWithPath: PathFormatter.expandTilde(rootPath), isDirectory: true)
        let resolvedBookmark = rootBookmarkData.flatMap(SecurityScopedBookmark.resolve)
        let scopedURL = resolvedBookmark ?? fallbackURL

        let didStart = scopedURL.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }

        if rootBookmarkData != nil, resolvedBookmark == nil || didStart == false {
            return SnapshotResult(discoveredCount: 0, repoIndex: .empty, accessDenied: true)
        }

        // Security-scoped bookmarks can resolve to file reference URLs (`/.file/id=…`).
        // FileManager APIs expect a path-based file URL for traversal.
        let rootURL = (scopedURL as NSURL).filePathURL ?? scopedURL
        let resolvedRoot = rootURL.resolvingSymlinksInPath().path

        let repoRoots = self.discoverRepoRoots(
            rootURL: rootURL,
            resolvedRoot: resolvedRoot,
            now: now,
            forceRescan: options.forceRescan,
            maxDepth: options.maxDepth
        )

        let (cachedStatuses, refreshRoots) = self.partitionStatusesToRefresh(
            repoRoots: repoRoots,
            now: now,
            options: options
        )

        let fetchTargets = self.fetchTargets(
            repoRoots: refreshRoots,
            fetchInterval: options.fetchInterval,
            now: now
        )

        let refreshedSnapshot = await LocalProjectsService().snapshot(
            repoRoots: refreshRoots,
            autoSyncEnabled: options.autoSyncEnabled,
            includeOnlyRepoNames: nil,
            concurrencyLimit: AppLimits.LocalRepo.snapshotConcurrencyLimit,
            fetchTargets: fetchTargets
        )

        for path in refreshedSnapshot.fetchedPaths {
            self.lastFetchByPath[path.path] = now
        }

        let enrichedRefreshed = refreshedSnapshot.statuses.map { status in
            status.withLastFetch(self.lastFetchByPath[status.path.path])
        }

        for status in enrichedRefreshed {
            self.statusCache[status.path.path] = StatusCacheEntry(status: status, updatedAt: now)
        }

        for status in refreshedSnapshot.syncAttemptedStatuses {
            await self.notifier.notifySync(for: status)
        }

        let enrichedCached = cachedStatuses.map { status in
            status.withLastFetch(self.lastFetchByPath[status.path.path])
        }
        let allStatuses = enrichedCached + enrichedRefreshed
        return SnapshotResult(
            discoveredCount: repoRoots.count,
            repoIndex: LocalRepoIndex(
                statuses: allStatuses,
                preferredPathsByFullName: options.preferredPathsByFullName
            ),
            accessDenied: false
        )
    }

    private struct DiscoveryCacheEntry {
        let repoRoots: [URL]
        let discoveredAt: Date
    }

    private struct StatusCacheEntry {
        let status: LocalRepoStatus
        let updatedAt: Date
    }

    private func discoverRepoRoots(
        rootURL: URL,
        resolvedRoot: String,
        now: Date,
        forceRescan: Bool,
        maxDepth: Int
    ) -> [URL] {
        if forceRescan == false, let cached = self.discoveryCache[resolvedRoot] {
            if now.timeIntervalSince(cached.discoveredAt) < self.discoveryCacheTTL { return cached.repoRoots }
        }

        let roots = LocalProjectsService().discoverRepoRoots(
            rootURL: rootURL,
            maxDepth: max(1, maxDepth)
        )
        self.discoveryCache[resolvedRoot] = DiscoveryCacheEntry(repoRoots: roots, discoveredAt: now)
        return roots
    }

    private func partitionStatusesToRefresh(
        repoRoots: [URL],
        now: Date,
        options: SnapshotOptions
    ) -> (cached: [LocalRepoStatus], refresh: [URL]) {
        guard repoRoots.isEmpty == false else { return ([], []) }

        let matchKeys = Set(options.matchRepoNames.map { $0.lowercased() })
        let interesting: [URL] = if matchKeys.isEmpty {
            []
        } else {
            repoRoots.filter { matchKeys.contains($0.lastPathComponent.lowercased()) }
        }

        var cached: [LocalRepoStatus] = []
        var refresh: [URL] = []
        cached.reserveCapacity(interesting.count)
        refresh.reserveCapacity(interesting.count)

        for repoURL in interesting {
            let key = repoURL.path
            guard let entry = self.statusCache[key] else {
                refresh.append(repoURL)
                continue
            }

            if options.forceRescan {
                refresh.append(repoURL)
                continue
            }

            if options.autoSyncEnabled, entry.status.canAutoSync {
                refresh.append(repoURL)
                continue
            }

            if options.fetchInterval > 0, self.needsFetch(for: repoURL, now: now, interval: options.fetchInterval) {
                refresh.append(repoURL)
                continue
            }

            if now.timeIntervalSince(entry.updatedAt) < self.statusCacheTTL {
                cached.append(entry.status)
            } else {
                refresh.append(repoURL)
            }
        }

        return (cached, refresh)
    }

    private func needsFetch(for repoURL: URL, now: Date, interval: TimeInterval) -> Bool {
        guard interval > 0 else { return false }
        let lastFetch = self.lastFetchByPath[repoURL.path]
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= interval
    }

    private func fetchTargets(
        repoRoots: [URL],
        fetchInterval: TimeInterval,
        now: Date
    ) -> Set<URL> {
        guard fetchInterval > 0 else { return [] }
        return Set(repoRoots.filter { self.needsFetch(for: $0, now: now, interval: fetchInterval) })
    }
}
