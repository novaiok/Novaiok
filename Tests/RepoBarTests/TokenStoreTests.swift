import Foundation
@testable import RepoBarCore
import Testing

struct TokenStoreTests {
    @Test
    func saveLoadFallsBackWithoutAccessGroupEntitlement() throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service, accessGroup: "com.steipete.repobar.shared")
        defer { store.clear() }

        let tokens = OAuthTokens(
            accessToken: "token-\(UUID().uuidString)",
            refreshToken: "refresh-\(UUID().uuidString)",
            expiresAt: Date().addingTimeInterval(3600)
        )

        try store.save(tokens: tokens)
        let loaded = try store.load()
        #expect(loaded == tokens)
    }
}
