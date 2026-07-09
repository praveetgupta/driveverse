import Foundation
import Combine
import CryptoKit
import Security
#if os(iOS)
import AuthenticationServices
import UIKit
#endif

// MARK: - PKCE (RFC 7636)

enum PKCE {
    /// 64 characters from the RFC 7636 unreserved set.
    static func randomVerifier() -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        var bytes = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return String(bytes.map { charset[Int($0) % charset.count] })
    }

    /// S256: BASE64URL(SHA256(ASCII(verifier))), no padding.
    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Token model & policy

struct SpotifyToken: Codable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
}

enum TokenAction: Equatable {
    case useCurrent
    case refresh
    case reauthorize
}

enum SpotifyTokenPolicy {
    /// Refresh this long before actual expiry so in-flight requests don't 401.
    static let expiryMargin: TimeInterval = 60

    static func action(for token: SpotifyToken?, now: Date) -> TokenAction {
        guard let token else { return .reauthorize }
        return now < token.expiresAt.addingTimeInterval(-expiryMargin) ? .useCurrent : .refresh
    }
}

// MARK: - Token storage

protocol TokenStore: AnyObject {
    func load() -> SpotifyToken?
    func save(_ token: SpotifyToken)
    func clear()
}

/// Used by unit tests and SwiftUI previews.
final class InMemoryTokenStore: TokenStore {
    var token: SpotifyToken?
    func load() -> SpotifyToken? { token }
    func save(_ token: SpotifyToken) { self.token = token }
    func clear() { token = nil }
}

final class KeychainTokenStore: TokenStore {
    private let service = "com.praveet.driveverse.spotify"
    private let account = "token"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func load() -> SpotifyToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(SpotifyToken.self, from: data)
    }

    func save(_ token: SpotifyToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        // Drive Mode polls Spotify while the phone is locked; the default
        // (WhenUnlocked) makes those reads fail and triggers spurious
        // reconnect banners mid-drive.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

// MARK: - Token endpoint client

enum SpotifyAuthError: Error, Equatable {
    case missingClientID
    case invalidCallback
    case notConnected
    case http(Int)
    /// Spotify rejected the refresh token — the user must reconnect.
    case refreshRejected
}

/// Talks to accounts.spotify.com/api/token. Pure request/response — the
/// session is injected so tests can stub it.
struct SpotifyTokenClient {
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    private struct TokenResponse: Decodable {
        let access_token: String
        let refresh_token: String?
        let expires_in: Int
    }

    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func exchangeCode(_ code: String, verifier: String, clientID: String, redirectURI: String, now: Date = Date()) async throws -> SpotifyToken {
        let response = try await post([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ])
        guard let refresh = response.refresh_token else { throw SpotifyAuthError.invalidCallback }
        return SpotifyToken(
            accessToken: response.access_token,
            refreshToken: refresh,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    /// PKCE refresh can rotate the refresh token; keep the old one if the
    /// response omits it.
    func refresh(_ token: SpotifyToken, clientID: String, now: Date = Date()) async throws -> SpotifyToken {
        let response: TokenResponse
        do {
            response = try await post([
                "grant_type": "refresh_token",
                "refresh_token": token.refreshToken,
                "client_id": clientID,
            ])
        } catch SpotifyAuthError.http(let status) where status == 400 || status == 401 {
            throw SpotifyAuthError.refreshRejected
        }
        return SpotifyToken(
            accessToken: response.access_token,
            refreshToken: response.refresh_token ?? token.refreshToken,
            expiresAt: now.addingTimeInterval(TimeInterval(response.expires_in))
        )
    }

    private func post(_ params: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(params)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode == 200 else { throw SpotifyAuthError.http(http.statusCode) }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }

    static func formBody(_ params: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return Data(
            params
                .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
                .sorted()
                .joined(separator: "&")
                .utf8
        )
    }
}

// MARK: - Secrets

enum SecretsLoader {
    /// Reads the Spotify client ID from Secrets.plist (gitignored — see
    /// Secrets.example.plist). Never hardcoded, per CLAUDE.md §2.8.
    static var spotifyClientID: String? {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let dict = NSDictionary(contentsOf: url) as? [String: Any],
              let id = dict["SpotifyClientID"] as? String,
              !id.isEmpty, id != "YOUR_SPOTIFY_CLIENT_ID" else {
            return nil
        }
        return id
    }
}

// MARK: - Auth manager

/// Owns the PKCE authorization flow, token persistence, and refresh.
@MainActor
final class SpotifyAuth: NSObject, ObservableObject {
    static let redirectURI = "driveverse://callback"
    static let callbackScheme = "driveverse"
    static let scopes = "user-read-currently-playing user-read-playback-state"
    /// A 401 arriving this soon after a successful refresh means the grant
    /// itself is dead — reconnect instead of refresh-looping.
    static let revokedWindow: TimeInterval = 30

    @Published private(set) var isConnected: Bool
    @Published var needsReconnect = false

    let clientID: String?
    private let store: TokenStore
    private let tokenClient: SpotifyTokenClient
    private var refreshTask: Task<SpotifyToken, Error>?
    private var lastRefreshAt: Date?
    var now: () -> Date = Date.init

    init(
        store: TokenStore = KeychainTokenStore(),
        session: URLSession = .shared,
        clientID: String? = SecretsLoader.spotifyClientID
    ) {
        self.store = store
        self.tokenClient = SpotifyTokenClient(session: session)
        self.clientID = clientID
        self.isConnected = store.load() != nil
        super.init()
    }

    var hasClientID: Bool { clientID != nil }

    func disconnect() {
        store.clear()
        isConnected = false
        needsReconnect = false
    }

    /// Returns a token valid for at least SpotifyTokenPolicy.expiryMargin,
    /// refreshing first when needed.
    func validAccessToken() async throws -> String {
        let token = store.load()
        switch SpotifyTokenPolicy.action(for: token, now: now()) {
        case .useCurrent:
            if needsReconnect { needsReconnect = false }
            return token!.accessToken
        case .refresh:
            return try await refreshNow().accessToken
        case .reauthorize:
            if isConnected { needsReconnect = true }
            throw SpotifyAuthError.notConnected
        }
    }

    /// Called when the API returns 401 despite a policy-valid token.
    func handleUnauthorized() async {
        if let last = lastRefreshAt, now().timeIntervalSince(last) < Self.revokedWindow {
            // Fresh token still rejected — the grant was revoked.
            store.clear()
            isConnected = false
            needsReconnect = true
            return
        }
        _ = try? await refreshNow() // refreshNow flags reconnect on rejection
    }

    /// Single-flight refresh: concurrent callers share one request.
    func refreshNow() async throws -> SpotifyToken {
        if let task = refreshTask {
            return try await task.value
        }
        guard let token = store.load(), let clientID else {
            throw SpotifyAuthError.notConnected
        }
        let client = tokenClient
        let task = Task { try await client.refresh(token, clientID: clientID) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let newToken = try await task.value
            store.save(newToken)
            lastRefreshAt = now()
            isConnected = true
            if needsReconnect { needsReconnect = false }
            return newToken
        } catch SpotifyAuthError.refreshRejected {
            store.clear()
            isConnected = false
            needsReconnect = true
            throw SpotifyAuthError.refreshRejected
        }
    }

#if os(iOS)
    private var webSession: ASWebAuthenticationSession?
    private let presenter = WebAuthPresenter()

    /// Full authorization-code-with-PKCE flow via ASWebAuthenticationSession.
    func connect() async throws {
        guard let clientID else { throw SpotifyAuthError.missingClientID }

        let verifier = PKCE.randomVerifier()
        let state = UUID().uuidString
        var comps = URLComponents(string: "https://accounts.spotify.com/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: PKCE.challenge(for: verifier)),
            URLQueryItem(name: "state", value: state),
        ]

        let callback = try await authenticate(url: comps.url!)
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems
        guard items?.first(where: { $0.name == "state" })?.value == state,
              let code = items?.first(where: { $0.name == "code" })?.value else {
            throw SpotifyAuthError.invalidCallback
        }

        let token = try await tokenClient.exchangeCode(
            code, verifier: verifier, clientID: clientID, redirectURI: Self.redirectURI
        )
        store.save(token)
        lastRefreshAt = now()
        isConnected = true
        needsReconnect = false
    }

    private func authenticate(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: error ?? SpotifyAuthError.invalidCallback)
                }
            }
            session.presentationContextProvider = presenter
            self.webSession = session
            session.start()
        }
    }
#endif
}

#if os(iOS)
private final class WebAuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif
