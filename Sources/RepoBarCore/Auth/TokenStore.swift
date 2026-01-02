import Foundation
import Logging
import Security

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date?

    public init(accessToken: String, refreshToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct OAuthClientCredentials: Codable, Equatable, Sendable {
    public let clientID: String
    public let clientSecret: String

    public init(clientID: String, clientSecret: String) {
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

public enum TokenStoreError: Error {
    case saveFailed
    case loadFailed
}

public struct TokenStore: Sendable {
    public static var shared: TokenStore { TokenStore() }
    private let service: String
    private let accessGroup: String?
    private let logger = RepoBarLogging.logger("token-store")

    public init(
        service: String = "com.steipete.repobar.auth",
        accessGroup: String? = nil
    ) {
        self.service = service
        self.accessGroup = accessGroup ?? Self.defaultAccessGroup()
    }

    public func save(tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)
        try self.save(data: data, account: "default")
    }

    public func load() throws -> OAuthTokens? {
        guard let data = try self.loadData(account: "default") else { return nil }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    public func save(clientCredentials: OAuthClientCredentials) throws {
        let data = try JSONEncoder().encode(clientCredentials)
        try self.save(data: data, account: "client")
    }

    public func loadClientCredentials() throws -> OAuthClientCredentials? {
        guard let data = try self.loadData(account: "client") else { return nil }
        return try JSONDecoder().decode(OAuthClientCredentials.self, from: data)
    }

    public func clear() {
        self.clear(account: "default")
        self.clear(account: "client")
    }
}

extension TokenStore {
    static let sharedAccessGroupSuffix = "com.steipete.repobar.shared"

    static func defaultAccessGroup() -> String? {
        #if os(macOS)
            guard let task = SecTaskCreateFromSelf(nil),
                  let entitlement = SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil)
            else {
                return nil
            }
            if let groups = entitlement as? [String] {
                return groups.first(where: { $0.hasSuffix(Self.sharedAccessGroupSuffix) })
            }
            return nil
        #else
            if let group = Bundle.main.object(forInfoDictionaryKey: "RepoBarKeychainAccessGroup") as? String {
                if group.isEmpty == false {
                    return group
                }
            }
            return nil
        #endif
    }
}

private extension TokenStore {
    func save(data: Data, account: String) throws {
        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            let query = self.baseQuery(account: account, accessGroup: group)
            let attributes: [CFString: Any] = [kSecValueData: data]
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            var status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecDuplicateItem {
                status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            }
            if status == errSecSuccess { return }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("save", status: lastStatus)
        throw TokenStoreError.saveFailed
    }

    func loadData(account: String) throws -> Data? {
        let accessGroups = self.accessGroupsForOperation()
        var lastStatus: OSStatus = errSecSuccess
        for (index, group) in accessGroups.enumerated() {
            var query = self.baseQuery(account: account, accessGroup: group)
            query[kSecReturnData] = true
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound {
                if index == accessGroups.count - 1 { return nil }
                continue
            }
            if status == errSecSuccess, let data = item as? Data { return data }
            lastStatus = status
            let isFinalAttempt = index == accessGroups.count - 1
            if isFinalAttempt || self.shouldRetryWithoutAccessGroup(status: status, accessGroup: group) == false {
                break
            }
        }
        self.logFailure("load", status: lastStatus)
        throw TokenStoreError.loadFailed
    }

    func clear(account: String) {
        let accessGroups = self.accessGroupsForOperation()
        for group in accessGroups {
            let query = self.baseQuery(account: account, accessGroup: group)
            SecItemDelete(query as CFDictionary)
        }
    }

    func accessGroupsForOperation() -> [String?] {
        guard let accessGroup else { return [nil] }
        return [accessGroup, nil]
    }

    func baseQuery(account: String, accessGroup: String?) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        return query
    }

    func shouldRetryWithoutAccessGroup(status: OSStatus, accessGroup: String?) -> Bool {
        guard accessGroup != nil else { return false }
        switch status {
        case errSecMissingEntitlement, errSecInteractionNotAllowed:
            return true
        default:
            return false
        }
    }

    func logFailure(_ action: String, status: OSStatus) {
        guard status != errSecSuccess else { return }
        let statusMessage = SecCopyErrorMessageString(status, nil) as String?
        if let statusMessage {
            self.logger.error("Keychain \(action) failed: \(statusMessage)")
        } else {
            self.logger.error("Keychain \(action) failed: OSStatus \(status)")
        }
    }
}
