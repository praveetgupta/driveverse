import Testing
import Foundation
@testable import DriveVerse

@Suite struct PKCETests {
    @Test func rfc7636AppendixBVector() {
        // Official test vector from RFC 7636 Appendix B.
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierShape() {
        let v1 = PKCE.randomVerifier()
        let v2 = PKCE.randomVerifier()
        #expect(v1.count == 64)
        #expect(v1 != v2)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect(v1.allSatisfy { allowed.contains($0) })
    }

    @Test func challengeIsBase64URLWithoutPadding() {
        let challenge = PKCE.challenge(for: PKCE.randomVerifier())
        #expect(challenge.count == 43) // SHA256 → 32 bytes → 43 base64url chars
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }
}

@Suite struct SpotifyTokenPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 780_000_000)

    private func token(expiresIn: TimeInterval) -> SpotifyToken {
        SpotifyToken(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(expiresIn))
    }

    @Test func missingTokenRequiresLogin() {
        #expect(SpotifyTokenPolicy.action(for: nil, now: now) == .reauthorize)
    }

    @Test func freshTokenUsedDirectly() {
        #expect(SpotifyTokenPolicy.action(for: token(expiresIn: 3600), now: now) == .useCurrent)
    }

    @Test func tokenInsideExpiryMarginRefreshes() {
        #expect(SpotifyTokenPolicy.action(for: token(expiresIn: 30), now: now) == .refresh)
    }

    @Test func expiredTokenRefreshes() {
        #expect(SpotifyTokenPolicy.action(for: token(expiresIn: -3600), now: now) == .refresh)
    }
}

private func drainBody(_ request: URLRequest) -> String {
    if let data = request.httpBody {
        return String(data: data, encoding: .utf8) ?? ""
    }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let n = stream.read(&buffer, maxLength: buffer.count)
        guard n > 0 else { break }
        data.append(buffer, count: n)
    }
    return String(data: data, encoding: .utf8) ?? ""
}

extension HTTPStubbedTests {
@Suite struct SpotifyAuthRefreshTests {
    @MainActor
    private func makeAuth(expiresIn: TimeInterval) -> (SpotifyAuth, InMemoryTokenStore) {
        let store = InMemoryTokenStore()
        store.save(SpotifyToken(
            accessToken: "old-access", refreshToken: "old-refresh",
            expiresAt: Date().addingTimeInterval(expiresIn)
        ))
        let auth = SpotifyAuth(
            store: store,
            session: StubURLProtocol.makeSession(),
            clientID: "client123"
        )
        return (auth, store)
    }

    @MainActor @Test func freshTokenSkipsNetwork() async throws {
        StubURLProtocol.reset { _ in (500, Data()) }
        let (auth, _) = makeAuth(expiresIn: 3600)
        let access = try await auth.validAccessToken()
        #expect(access == "old-access")
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @MainActor @Test func expiredTokenIsRefreshed() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8))
        }
        let (auth, store) = makeAuth(expiresIn: -60)

        let access = try await auth.validAccessToken()
        #expect(access == "new-access")
        #expect(store.token?.accessToken == "new-access")
        #expect(store.token?.refreshToken == "new-refresh")
        #expect(auth.isConnected)
        #expect(!auth.needsReconnect)

        let request = try #require(StubURLProtocol.requests.first)
        #expect(request.url == SpotifyTokenClient.tokenURL)
        let body = drainBody(request)
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=old-refresh"))
        #expect(body.contains("client_id=client123"))
    }

    @MainActor @Test func reconnectBannerClearsWhenTokenReadable() async throws {
        // A locked-phone Keychain miss raises the banner; it must clear on
        // the next successful read instead of sticking until manual reconnect.
        StubURLProtocol.reset { _ in (500, Data()) }
        let (auth, _) = makeAuth(expiresIn: 3600)
        auth.needsReconnect = true
        _ = try await auth.validAccessToken()
        #expect(!auth.needsReconnect)
    }

    @MainActor @Test func reconnectBannerClearsOnSuccessfulRefresh() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8))
        }
        let (auth, _) = makeAuth(expiresIn: -60)
        auth.needsReconnect = true
        _ = try await auth.validAccessToken()
        #expect(!auth.needsReconnect)
    }

    @MainActor @Test func rotatedRefreshTokenKeptWhenOmitted() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"access_token":"new-access","expires_in":3600}"#.utf8))
        }
        let (auth, store) = makeAuth(expiresIn: -60)
        _ = try await auth.validAccessToken()
        #expect(store.token?.refreshToken == "old-refresh")
    }

    @MainActor @Test func rejectedRefreshRequiresReconnect() async {
        StubURLProtocol.reset { _ in
            (400, Data(#"{"error":"invalid_grant"}"#.utf8))
        }
        let (auth, store) = makeAuth(expiresIn: -60)

        await #expect(throws: SpotifyAuthError.refreshRejected) {
            _ = try await auth.validAccessToken()
        }
        #expect(store.token == nil)
        #expect(!auth.isConnected)
        #expect(auth.needsReconnect)
    }

    @MainActor @Test func noTokenThrowsNotConnected() async {
        StubURLProtocol.reset { _ in (500, Data()) }
        let auth = SpotifyAuth(
            store: InMemoryTokenStore(),
            session: StubURLProtocol.makeSession(),
            clientID: "client123"
        )
        await #expect(throws: SpotifyAuthError.notConnected) {
            _ = try await auth.validAccessToken()
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @MainActor @Test func codeExchangeBuildsCorrectRequest() async throws {
        StubURLProtocol.reset { _ in
            (200, Data(#"{"access_token":"acc","refresh_token":"ref","expires_in":3600}"#.utf8))
        }
        let client = SpotifyTokenClient(session: StubURLProtocol.makeSession())
        let t0 = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let token = try await client.exchangeCode(
            "auth-code", verifier: "the-verifier", clientID: "client123",
            redirectURI: "driveverse://callback", now: t0
        )
        #expect(token == SpotifyToken(accessToken: "acc", refreshToken: "ref", expiresAt: t0.addingTimeInterval(3600)))

        let body = drainBody(try #require(StubURLProtocol.requests.first))
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code=auth-code"))
        #expect(body.contains("code_verifier=the-verifier"))
        #expect(body.contains("redirect_uri=driveverse%3A%2F%2Fcallback"))
    }
}
}
