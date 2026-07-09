import Foundation
import Combine

enum SourcePin: String, CaseIterable, Identifiable {
    case auto
    case appleMusic
    case spotify

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Automatic"
        case .appleMusic: return "Apple Music"
        case .spotify: return "Spotify"
        }
    }
}

/// Pure arbitration per CLAUDE.md §4.4:
/// Apple Music playing wins (local, exact position) → Spotify playing →
/// otherwise keep the last known track, marked not playing.
enum NowPlayingArbiter {
    static func arbitrate(
        apple: NowPlayingState?,
        spotify: NowPlayingState?,
        pin: SourcePin,
        previous: NowPlayingState?
    ) -> NowPlayingState? {
        switch pin {
        case .appleMusic:
            return apple ?? carryOver(previous, matching: .appleMusic)
        case .spotify:
            return spotify ?? carryOver(previous, matching: .spotify)
        case .auto:
            if let apple, apple.isPlaying { return apple }
            if let spotify, spotify.isPlaying { return spotify }
            // Both idle: prefer a source still reporting an item, else the
            // last known state — always flagged as not playing.
            return (apple ?? spotify ?? previous)?.with(isPlaying: false)
        }
    }

    private static func carryOver(_ previous: NowPlayingState?, matching source: MusicSource) -> NowPlayingState? {
        guard let previous, previous.source == source else { return nil }
        return previous.with(isPlaying: false)
    }
}

/// Combines both sources' publishers through the arbiter and republishes the
/// winner. The pin can be changed at runtime from Settings.
final class NowPlayingCoordinator {
    private let subject = CurrentValueSubject<NowPlayingState?, Never>(nil)
    var statePublisher: AnyPublisher<NowPlayingState?, Never> {
        subject.removeDuplicates().eraseToAnyPublisher()
    }

    private let pinSubject: CurrentValueSubject<SourcePin, Never>
    var pin: SourcePin {
        get { pinSubject.value }
        set { pinSubject.send(newValue) }
    }

    private var cancellable: AnyCancellable?

    init(
        applePublisher: AnyPublisher<NowPlayingState?, Never>,
        spotifyPublisher: AnyPublisher<NowPlayingState?, Never>,
        pin: SourcePin = .auto
    ) {
        pinSubject = CurrentValueSubject(pin)
        cancellable = Publishers.CombineLatest3(applePublisher, spotifyPublisher, pinSubject)
            .map { [subject] apple, spotify, pin in
                NowPlayingArbiter.arbitrate(
                    apple: apple, spotify: spotify,
                    pin: pin, previous: subject.value
                )
            }
            .sink { [subject] state in subject.send(state) }
    }
}
