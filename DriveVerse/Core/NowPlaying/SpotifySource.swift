import Foundation
import Combine

@MainActor
protocol SpotifyTokenProviding: AnyObject {
    var isConnected: Bool { get }
    func validAccessToken() async throws -> String
    func handleUnauthorized() async
}

extension SpotifyAuth: SpotifyTokenProviding {}

/// Polls the Spotify Web API's currently-playing endpoint. 5 s while Spotify
/// is playing, 15 s while idle-probing, per CLAUDE.md §4.3. Never talks to the
/// Spotify app — Web API only, Developer-Mode app, account owner.
final class SpotifySource: NowPlayingSource {
    static let endpoint = URL(string: "https://api.spotify.com/v1/me/player/currently-playing")!
    static let defaultActiveInterval: TimeInterval = 5
    static let idleInterval: TimeInterval = 15

    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { subject.eraseToAnyPublisher() }

    private let session: URLSession
    private let tokenProvider: any SpotifyTokenProviding
    /// Settings-backed (3–10 s); read each cycle so changes apply immediately.
    var activeInterval: () -> TimeInterval = { SpotifySource.defaultActiveInterval }

    private var pollTask: Task<Void, Never>?

    init(session: URLSession = .shared, tokenProvider: any SpotifyTokenProviding) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let delay = await self.pollOnce()
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One poll; returns the delay until the next one.
    func pollOnce() async -> TimeInterval {
        guard await tokenProvider.isConnected else {
            subject.send(nil)
            return Self.idleInterval
        }
        let token: String
        do {
            token = try await tokenProvider.validAccessToken()
        } catch {
            subject.send(nil)
            return Self.idleInterval
        }

        var request = URLRequest(url: Self.endpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return Self.idleInterval }
            switch http.statusCode {
            case 200:
                let state = try Self.parseCurrentlyPlaying(data, capturedAt: Date())
                subject.send(state)
                return state?.isPlaying == true ? activeInterval() : Self.idleInterval
            case 204: // nothing playing
                subject.send(nil)
                return Self.idleInterval
            case 401:
                await tokenProvider.handleUnauthorized()
                subject.send(nil)
                return Self.idleInterval
            case 429:
                let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
                return max(retryAfter ?? Self.idleInterval, 1)
            default:
                return Self.idleInterval
            }
        } catch {
            // Transient network error (tunnel, dead zone) — just try again.
            return Self.idleInterval
        }
    }

    // MARK: - Parsing (pure, fixture-tested)

    static func parseCurrentlyPlaying(_ data: Data, capturedAt: Date) throws -> NowPlayingState? {
        struct Payload: Decodable {
            struct Item: Decodable {
                struct Artist: Decodable { let name: String }
                struct Album: Decodable { let name: String? }
                let name: String
                let duration_ms: Int?
                let artists: [Artist]?
                let album: Album?
            }
            let progress_ms: Int?
            let is_playing: Bool?
            let item: Item?
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let item = payload.item else { return nil } // e.g. private session or ad
        return NowPlayingState(
            title: item.name,
            artist: item.artists?.first?.name ?? "",
            album: item.album?.name,
            durationMs: item.duration_ms,
            positionMs: payload.progress_ms ?? 0,
            isPlaying: payload.is_playing ?? false,
            source: .spotify,
            capturedAt: capturedAt
        )
    }
}
