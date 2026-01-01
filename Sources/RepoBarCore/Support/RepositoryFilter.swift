import Foundation

public enum RepositoryFilter {
    public static func apply(
        _ repos: [Repository],
        includeForks: Bool,
        includeArchived: Bool,
        pinned: Set<String> = [],
        onlyWith: RepositoryOnlyWith = .none,
        ownerFilter: [String] = []
    ) -> [Repository] {
        let needsFilter = includeForks == false || includeArchived == false || onlyWith.isActive || !ownerFilter.isEmpty
        guard needsFilter else { return repos }

        let ownerSet = Set(ownerFilter.map { $0.lowercased() })

        return repos.filter { repo in
            if pinned.contains(repo.fullName) { return true }
            if includeForks == false, repo.isFork { return false }
            if includeArchived == false, repo.isArchived { return false }
            if onlyWith.isActive, onlyWith.matches(repo) == false { return false }
            if !ownerSet.isEmpty, !ownerSet.contains(repo.owner.lowercased()) { return false }
            return true
        }
    }
}
