import Foundation
@testable import RepoBar
import RepoBarCore
import Testing

struct OwnerFilteringTests {
    @Test
    func repositoryFilterIncludesAllWhenOwnerFilterIsEmpty() {
        let repos = [
            Self.repo(owner: "alice", name: "A"),
            Self.repo(owner: "bob", name: "B"),
            Self.repo(owner: "charlie", name: "C")
        ]
        let filtered = RepositoryFilter.apply(
            repos,
            includeForks: true,
            includeArchived: true,
            ownerFilter: []
        )
        #expect(filtered.count == 3)
    }

    @Test
    func repositoryFilterIncludesOnlySpecifiedOwner() {
        let repos = [
            Self.repo(owner: "alice", name: "A"),
            Self.repo(owner: "bob", name: "B"),
            Self.repo(owner: "charlie", name: "C")
        ]
        let filtered = RepositoryFilter.apply(
            repos,
            includeForks: true,
            includeArchived: true,
            ownerFilter: ["alice"]
        )
        #expect(filtered.count == 1)
        #expect(filtered.first?.owner == "alice")
    }

    @Test
    func repositoryFilterIncludesMultipleSpecifiedOwners() {
        let repos = [
            Self.repo(owner: "alice", name: "A"),
            Self.repo(owner: "bob", name: "B"),
            Self.repo(owner: "charlie", name: "C"),
            Self.repo(owner: "alice", name: "D")
        ]
        let filtered = RepositoryFilter.apply(
            repos,
            includeForks: true,
            includeArchived: true,
            ownerFilter: ["alice", "charlie"]
        )
        #expect(filtered.count == 3)
        #expect(filtered.map(\.owner).sorted() == ["alice", "alice", "charlie"])
    }

    @Test
    func repositoryFilterIsCaseInsensitive() {
        let repos = [
            Self.repo(owner: "Alice", name: "A"),
            Self.repo(owner: "BOB", name: "B"),
            Self.repo(owner: "charlie", name: "C")
        ]
        let filtered = RepositoryFilter.apply(
            repos,
            includeForks: true,
            includeArchived: true,
            ownerFilter: ["alice", "bob"]
        )
        #expect(filtered.count == 2)
    }

    @Test
    func repositoryFilterKeepsPinnedReposRegardlessOfOwner() {
        let pinnedRepo = Self.repo(owner: "dotnet", name: "Pinned")
        let otherRepo = Self.repo(owner: "dotnet", name: "Other")
        let myRepo = Self.repo(owner: "me", name: "Mine")

        let filtered = RepositoryFilter.apply(
            [pinnedRepo, otherRepo, myRepo],
            includeForks: true,
            includeArchived: true,
            pinned: Set([pinnedRepo.fullName]),
            ownerFilter: ["me"]
        )
        #expect(filtered.count == 2)
        #expect(filtered.map(\.fullName).sorted() == [myRepo.fullName, pinnedRepo.fullName].sorted())
    }

    @Test
    func selectVisibleAppliesOwnerFilter() {
        let myRepo1 = Self.repo(owner: "me", name: "Repo1")
        let myRepo2 = Self.repo(owner: "me", name: "Repo2")
        let orgRepo1 = Self.repo(owner: "dotnet", name: "AspNetCore")
        let orgRepo2 = Self.repo(owner: "microsoft", name: "TypeScript")

        let visible = AppState.selectVisible(
            all: [myRepo1, orgRepo1, myRepo2, orgRepo2],
            options: AppState.VisibleSelectionOptions(
                pinned: [],
                hidden: [],
                includeForks: true,
                includeArchived: true,
                limit: 10,
                ownerFilter: ["me"]
            )
        )

        #expect(visible.count == 2)
        #expect(visible.map(\.owner).allSatisfy { $0 == "me" })
    }

    @Test
    func repositoryPipelineAppliesOwnerFilter() {
        let repos = [
            Self.repo(owner: "alice", name: "A"),
            Self.repo(owner: "bob", name: "B"),
            Self.repo(owner: "charlie", name: "C")
        ]
        let query = RepositoryQuery(
            scope: .all,
            onlyWith: .none,
            includeForks: true,
            includeArchived: true,
            sortKey: .name,
            limit: nil,
            ageCutoff: nil,
            pinned: [],
            hidden: [],
            pinPriority: false,
            ownerFilter: ["alice", "bob"]
        )
        let filtered = RepositoryPipeline.apply(repos, query: query)
        #expect(filtered.count == 2)
        #expect(filtered.map(\.owner).sorted() == ["alice", "bob"])
    }
}

private extension OwnerFilteringTests {
    static func repo(owner: String, name: String) -> Repository {
        Repository(
            id: UUID().uuidString,
            name: name,
            owner: owner,
            isFork: false,
            isArchived: false,
            sortOrder: nil,
            error: nil,
            rateLimitedUntil: nil,
            ciStatus: .unknown,
            ciRunCount: nil,
            openIssues: 0,
            openPulls: 0,
            stars: 0,
            pushedAt: nil,
            latestRelease: nil,
            latestActivity: nil,
            traffic: nil,
            heatmap: []
        )
    }
}
