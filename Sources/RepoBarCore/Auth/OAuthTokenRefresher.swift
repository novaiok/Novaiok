import Foundation

public struct OAuthTokenRefresher: Sendable {
    private let tokenStore: TokenStore
    private let load: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public init(
        tokenStore: TokenStore = .shared,
        load: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse) = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.tokenStore = tokenStore
        self.load = load
    }

    public func refreshIfNeeded(host: URL, force: Bool = false) async throws -> OAuthTokens? {
        guard var tokens = try tokenStore.load() else { return nil }
        if tokens.refreshToken.isEmpty {
            return tokens
        }
        if force == false, let expiry = tokens.expiresAt, expiry > Date().addingTimeInterval(60) {
            return tokens
        }

        let credentials = try tokenStore.loadClientCredentials()
            ?? OAuthClientCredentials(clientID: RepoBarAuthDefaults.clientID, clientSecret: RepoBarAuthDefaults.clientSecret)

        let base = host.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let refreshURL = URL(string: "\(base)/login/oauth/access_token")!
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Accept")
        request.addValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formUrlEncoded([
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken
        ])

        let (data, responseAny) = try await self.load(request)
        guard let response = responseAny as? HTTPURLResponse else {
            throw GitHubAPIError.badStatus(code: -1, message: "GitHub returned an unexpected response.")
        }
        guard response.statusCode == 200 else {
            let detail = Self.refreshErrorDetail(from: data)
            let message = Self.refreshErrorMessage(status: response.statusCode, detail: detail)
            throw GitHubAPIError.badStatus(code: response.statusCode, message: message)
        }
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            let expires = Date().addingTimeInterval(TimeInterval(decoded.expiresIn ?? 3600))
            tokens = OAuthTokens(
                accessToken: decoded.accessToken,
                refreshToken: decoded.refreshToken ?? tokens.refreshToken,
                expiresAt: expires
            )
            try self.tokenStore.save(tokens: tokens)
            return tokens
        } catch {
            let detail = Self.refreshErrorDetail(from: data)
            let message = Self.refreshDecodeFailureMessage(detail: detail)
            throw GitHubAPIError.badStatus(code: response.statusCode, message: message)
        }
    }
}

private extension OAuthTokenRefresher {
    static func formUrlEncoded(_ params: [String: String]) -> Data? {
        let encoded = params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
        return encoded.data(using: .utf8)
    }

    static func refreshErrorDetail(from data: Data) -> String? {
        if let decoded = try? JSONDecoder().decode(OAuthErrorResponse.self, from: data) {
            let error = decoded.errorDescription ?? decoded.message ?? decoded.error
            return error.flatMap(Self.cleaned)
        }
        if let text = String(data: data, encoding: .utf8) {
            return self.cleaned(text)
        }
        return nil
    }

    static func refreshErrorMessage(status: Int, detail: String?) -> String {
        if let detail, detail.isEmpty == false {
            return "Authentication refresh failed (HTTP \(status)). \(detail) Please sign in again."
        }
        return "Authentication refresh failed (HTTP \(status)). Please sign in again."
    }

    static func refreshDecodeFailureMessage(detail: String?) -> String {
        if let detail, detail.isEmpty == false {
            return "Authentication refresh failed. \(detail) Please sign in again."
        }
        return "Authentication refresh failed. Please sign in again."
    }

    static func cleaned(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let expiresIn: Int?
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct OAuthErrorResponse: Decodable {
    let error: String?
    let errorDescription: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case message
    }
}
