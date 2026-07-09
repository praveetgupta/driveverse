import Foundation
import Combine

enum LyricsDisplayState: Equatable {
    case idle       // nothing playing yet
    case loading
    case synced([LRCLine])
    case plain(String)
    case instrumental
    case notFound
    case failed
}

/// Central wiring: sources → coordinator → sync engine → lyrics → UI
/// and Live Activity. (Drive Mode keep-alive is added in Phase 7.)
@MainActor
final class AppModel: ObservableObject {
    static let pollIntervalKey = "spotifyPollInterval"
    static let sourcePinKey = "sourcePin"

    // MARK: UI state

    @Published private(set) var nowPlaying: NowPlayingState?
    @Published private(set) var lyricsState: LyricsDisplayState = .idle
    @Published private(set) var position: LyricsPosition?
    @Published private(set) var appleMusicAuth: MediaAuthStatus = .unknown
    @Published private(set) var spotifyConnected = false
    @Published private(set) var spotifyNeedsReconnect = false
    @Published var errorMessage: String?
    @Published var driveMode = false {
        didSet { updateKeepAlive() }
    }

    var sourcePin: SourcePin {
        get { coordinator.pin }
        set {
            objectWillChange.send()
            coordinator.pin = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.sourcePinKey)
        }
    }

    // MARK: Pipeline

    let spotifyAuth: SpotifyAuth
    private let spotifySource: SpotifySource
#if os(iOS)
    private let appleSource: AppleMusicSource
    private let liveActivity = LiveActivityController()
    private let backgroundKeeper = BackgroundKeeper()
#endif
    private let coordinator: NowPlayingCoordinator
    private let syncEngine = SyncEngine()
    private let lyricsService = LyricsService()

    private var cancellables: Set<AnyCancellable> = []
    private var lyricsTask: Task<Void, Never>?
    private var currentSignature: String?
    private var started = false

    init() {
        let auth = SpotifyAuth()
        spotifyAuth = auth
        let spotify = SpotifySource(tokenProvider: auth)
        spotify.activeInterval = {
            let value = UserDefaults.standard.double(forKey: Self.pollIntervalKey)
            return (3...10).contains(value) ? value : SpotifySource.defaultActiveInterval
        }
        spotifySource = spotify

        let applePublisher: AnyPublisher<NowPlayingState?, Never>
#if os(iOS)
        let apple = AppleMusicSource()
        appleSource = apple
        applePublisher = apple.statePublisher
#else
        applePublisher = Just<NowPlayingState?>(nil).eraseToAnyPublisher()
#endif

        let savedPin = UserDefaults.standard.string(forKey: Self.sourcePinKey)
        coordinator = NowPlayingCoordinator(
            applePublisher: applePublisher,
            spotifyPublisher: spotify.statePublisher,
            pin: savedPin.flatMap(SourcePin.init(rawValue:)) ?? .auto
        )

        wire()
    }

    func start() {
        guard !started else { return }
        started = true
#if os(iOS)
        appleSource.start()
#endif
        spotifySource.start()
        syncEngine.startTicking()
    }

    // MARK: Actions

#if os(iOS)
    func connectSpotify() async {
        do {
            try await spotifyAuth.connect()
            errorMessage = nil
        } catch SpotifyAuthError.missingClientID {
            errorMessage = "No Spotify client ID. Copy Secrets.example.plist to Secrets.plist and fill in your ID."
        } catch {
            errorMessage = "Spotify connection failed. Try again."
        }
    }
#endif

    func disconnectSpotify() {
        spotifyAuth.disconnect()
    }

    func retryLyrics() {
        guard let state = nowPlaying else { return }
        currentSignature = LyricsMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        fetchLyrics(for: state)
    }

    func clearLyricsCache() {
        lyricsService.clearCache()
    }

    // MARK: Wiring

    private func wire() {
        coordinator.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.handle(state) }
            .store(in: &cancellables)

        syncEngine.positionSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] position in
                self?.position = position
                self?.syncLiveActivity()
            }
            .store(in: &cancellables)

        spotifyAuth.$isConnected
            .sink { [weak self] in self?.spotifyConnected = $0 }
            .store(in: &cancellables)
        spotifyAuth.$needsReconnect
            .sink { [weak self] in self?.spotifyNeedsReconnect = $0 }
            .store(in: &cancellables)

#if os(iOS)
        appleSource.authStatusSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.appleMusicAuth = $0 }
            .store(in: &cancellables)
#endif
    }

    private func handle(_ state: NowPlayingState?) {
        nowPlaying = state
        syncEngine.apply(state)

        guard let state else {
            currentSignature = nil
            lyricsTask?.cancel()
            syncEngine.setLyrics([])
            lyricsState = .idle
            return
        }

        let signature = LyricsMatcher.signature(
            title: state.title, artist: state.artist, durationMs: state.durationMs
        )
        if signature != currentSignature {
            currentSignature = signature
            fetchLyrics(for: state)
        }
        syncLiveActivity()
    }

    /// The controller's update policy dedupes the 500 ms ticks — only line
    /// changes and play/pause flips reach ActivityKit.
    private func syncLiveActivity() {
#if os(iOS)
        var hasSyncedLyrics = false
        if case .synced = lyricsState { hasSyncedLyrics = true }
        liveActivity.sync(state: nowPlaying, position: position, hasSyncedLyrics: hasSyncedLyrics)
        updateKeepAlive()
#endif
    }

    /// Per CLAUDE.md §6: the silent-audio keep-alive runs only while Drive
    /// Mode is on AND a Live Activity is active — never as a background default.
    private func updateKeepAlive() {
#if os(iOS)
        let shouldRun = driveMode && liveActivity.isActive
        if shouldRun && !backgroundKeeper.isRunning {
            do {
                try backgroundKeeper.start()
            } catch {
                driveMode = false
                errorMessage = "Couldn't start the Drive Mode audio session."
            }
        } else if !shouldRun && backgroundKeeper.isRunning {
            backgroundKeeper.stop()
        }
#endif
    }

    private func fetchLyrics(for state: NowPlayingState) {
        lyricsTask?.cancel()
        syncEngine.setLyrics([])
        lyricsState = .loading

        lyricsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.lyricsService.lyrics(for: state)
                guard !Task.isCancelled else { return }
                switch result {
                case .synced(let raw):
                    let lines = LRCParser.parse(raw)
                    if lines.isEmpty {
                        self.lyricsState = .notFound
                    } else {
                        self.lyricsState = .synced(lines)
                        self.syncEngine.setLyrics(lines)
                    }
                case .plain(let text):
                    self.lyricsState = .plain(text)
                case .instrumental:
                    self.lyricsState = .instrumental
                case .notFound:
                    self.lyricsState = .notFound
                }
            } catch is CancellationError {
                // superseded by a newer track — nothing to do
            } catch {
                guard !Task.isCancelled else { return }
                self.lyricsState = .failed
            }
        }
    }
}
