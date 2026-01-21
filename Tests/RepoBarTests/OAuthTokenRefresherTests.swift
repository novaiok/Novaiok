import Foundation
@testable import RepoBarCore
import Testing

struct OAuthTokenRefresherTests {
    @Test
    func refreshUsesStoredClientCredentials() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))
        try store.save(clientCredentials: OAuthClientCredentials(clientID: "cid", clientSecret: "csecret"))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString.contains("/login/oauth/access_token") == true)
            let body = try #require(Self.bodyString(from: request))
            #expect(body.contains("client_id=cid"))
            #expect(body.contains("client_secret=csecret"))
            #expect(body.contains("grant_type=refresh_token"))
            #expect(body.contains("refresh_token=r1"))

            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"access_token":"new","token_type":"bearer","scope":"repo","expires_in":3600,"refresh_token":"r2"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }
        let refreshed = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
        #expect(refreshed?.accessToken == "new")
        #expect(try store.load()?.refreshToken == "r2")
    }

    @Test
    func refreshFailureShowsHelpfulMessage() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"error":"invalid_grant","error_description":"refresh token revoked"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }

        do {
            _ = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
            #expect(Bool(false))
        } catch let error as GitHubAPIError {
            guard case let .badStatus(code, message) = error else {
                Issue.record("Expected GitHubAPIError.badStatus, got \(error)")
                return
            }
            #expect(code == 400)
            #expect(message?.contains("Please sign in again.") == true)
            #expect(message?.contains("refresh token revoked") == true)
        }
    }

    @Test
    func refreshFailureHandlesMalformedSuccessResponse() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        try store.save(tokens: OAuthTokens(accessToken: "old", refreshToken: "r1", expiresAt: .distantPast))

        let session = URLSession(configuration: Self.sessionConfiguration())
        let handlerID = UUID().uuidString
        Self.MockURLProtocol.register(handlerID: handlerID) { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = Data("""
            {"error":"invalid_grant","error_description":"refresh token revoked"}
            """.utf8)
            return (data, response)
        }
        defer { Self.MockURLProtocol.unregister(handlerID: handlerID) }

        let refresher = OAuthTokenRefresher(tokenStore: store) { request in
            let (tagged, boxed) = Self.taggedRequest(request, handlerID: handlerID)
            _ = boxed
            return try await session.data(for: tagged)
        }

        do {
            _ = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
            #expect(Bool(false))
        } catch let error as GitHubAPIError {
            guard case let .badStatus(code, message) = error else {
                Issue.record("Expected GitHubAPIError.badStatus, got \(error)")
                return
            }
            #expect(code == 200)
            #expect(message?.contains("Please sign in again.") == true)
            #expect(message?.contains("refresh token revoked") == true)
        }
    }

    @Test
    func refreshSkipsWhenRefreshTokenMissing() async throws {
        let service = "com.steipete.repobar.auth.tests.\(UUID().uuidString)"
        let store = TokenStore(service: service)
        defer { store.clear() }

        let tokens = OAuthTokens(accessToken: "tok", refreshToken: "", expiresAt: nil)
        try store.save(tokens: tokens)

        let refresher = OAuthTokenRefresher(tokenStore: store) { _ in
            throw URLError(.badServerResponse)
        }

        let refreshed = try await refresher.refreshIfNeeded(host: RepoBarAuthDefaults.githubHost)
        #expect(refreshed == tokens)
    }
}

private extension OAuthTokenRefresherTests {
    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return config
    }

    // swiftlint:disable static_over_final_class
    final class MockURLProtocol: URLProtocol {
        private static let handlersLock = NSLock()
        private nonisolated(unsafe) static var handlers: [String: @Sendable (URLRequest) throws -> (Data, URLResponse)] = [:]

        static func register(
            handlerID: String,
            handler: @escaping @Sendable (URLRequest) throws -> (Data, URLResponse)
        ) {
            self.handlersLock.lock()
            self.handlers[handlerID] = handler
            self.handlersLock.unlock()
        }

        static func unregister(handlerID: String) {
            self.handlersLock.lock()
            self.handlers[handlerID] = nil
            self.handlersLock.unlock()
        }

        override class func canInit(with request: URLRequest) -> Bool {
            URLProtocol.property(forKey: "handlerID", in: request) != nil
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            guard
                let handlerID = URLProtocol.property(forKey: "handlerID", in: request) as? String,
                let handler = Self.handler(for: handlerID)
            else {
                client?.urlProtocol(self, didFailWithError: URLError(.unsupportedURL))
                return
            }

            do {
                let (data, response) = try handler(request)
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }

        override func stopLoading() {}

        private static func handler(for handlerID: String) -> (@Sendable (URLRequest) throws -> (Data, URLResponse))? {
            self.handlersLock.lock()
            defer { handlersLock.unlock() }
            return self.handlers[handlerID]
        }
    }

    // swiftlint:enable static_over_final_class

    static func bodyString(from request: URLRequest) -> String? {
        if let body = request.httpBody, let string = String(data: body, encoding: .utf8) {
            return string
        }

        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4 * 1024
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8)
    }

    static func taggedRequest(_ request: URLRequest, handlerID: String) -> (URLRequest, NSMutableURLRequest) {
        let boxed = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(handlerID, forKey: "handlerID", in: boxed)
        return (boxed as URLRequest, boxed)
    }
}
