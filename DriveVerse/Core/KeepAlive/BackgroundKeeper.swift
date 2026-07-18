import Foundation

#if os(iOS)
import AVFoundation
import UIKit
import os

/// Keeps the app alive in the background during Drive Mode by looping a
/// silent WAV through AVAudioPlayer at volume 0. The session uses `.playback`
/// with `.mixWithOthers` so the real music (Apple Music / Spotify) is never
/// ducked or interrupted.
///
/// AVAudioPlayer (not AVAudioEngine) on purpose: the system reroutes a
/// playing AVAudioPlayer across route/configuration changes on its own,
/// whereas an engine stops silently and can only be restarted from contexts
/// that allow session activation — which the background is not.
///
/// ⚠️ App Store note (CLAUDE.md §6): a silent-audio keep-alive is fine for a
/// personally sideloaded build, but App Review rejects the `audio` background
/// mode when the app produces no audible content. A store build would need a
/// different strategy. That's why this runs only while the user has explicitly
/// toggled Drive Mode on — battery cost is opt-in.
final class BackgroundKeeper {
    private static let log = Logger(subsystem: "com.praveet.driveverse", category: "keepalive")

    private var player: AVAudioPlayer?
    private var observers: [NSObjectProtocol] = []
    private var heartbeat: Timer?
    private(set) var isRunning = false

    deinit {
        removeObservers()
        heartbeat?.invalidate()
    }

    func start() throws {
        guard !isRunning else { return }
        try activateAndPlay()
        isRunning = true
        installObservers()
        startHeartbeat()
        Self.log.notice("keep-alive started")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        heartbeat?.invalidate()
        heartbeat = nil
        player?.stop()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        Self.log.notice("keep-alive stopped")
    }

    private func activateAndPlay() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)

        let player = try AVAudioPlayer(data: Self.silentWAV)
        player.numberOfLoops = -1
        // Full volume on purpose: the samples are all zero, so this is just
        // as silent — but iOS is known to treat zero-volume playback as
        // "not really playing" and withhold background runtime for it.
        player.volume = 1
        player.prepareToPlay()
        guard player.play() else { throw CocoaError(.fileReadUnknown) }
        self.player = player
    }

    /// Interruptions (Siri, calls, alarms) pause the player; resume on .ended.
    /// A media-services crash invalidates the player entirely — rebuild it.
    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRunning else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            Self.log.notice("interruption: \(type == .began ? "began" : "ended", privacy: .public)")
            if type == .ended { self.recover(rebuild: false) }
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            Self.log.warning("media services reset — rebuilding player")
            self.recover(rebuild: true)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            // AVAudioPlayer keeps playing across route changes by itself;
            // log it, and nudge the player only if it actually stopped.
            let playing = self.player?.isPlaying ?? false
            Self.log.notice("route change (player playing: \(playing, privacy: .public))")
            if !playing { self.recover(rebuild: false) }
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func recover(rebuild: Bool) {
        if rebuild { player = nil }
        if let player, player.play() {
            Self.log.notice("recovered by resuming player")
            return
        }
        do {
            try activateAndPlay()
            Self.log.notice("recovered by reactivating session")
        } catch {
            Self.log.error("recovery failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Visible in Console.app: proof of background life. Silence in the log
    /// stream while Drive Mode is on = the process got suspended anyway.
    /// backgroundTimeRemaining is the verdict on whether iOS granted audio
    /// background execution: a huge value (~1.8e308) means yes; a value
    /// counting down from ~30 means we're on the ordinary suspension clock.
    private func startHeartbeat() {
        let timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            let playing = self.player?.isPlaying ?? false
            let remaining = UIApplication.shared.backgroundTimeRemaining
            let remainingText = remaining > 86_400 ? "unlimited" : String(format: "%.0fs", remaining)
            Self.log.notice("heartbeat (playing: \(playing, privacy: .public), bg time: \(remainingText, privacy: .public))")
            if self.isRunning, !playing {
                Self.log.warning("player found stopped — recovering")
                self.recover(rebuild: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeat = timer
    }

    /// 1 s of 8 kHz mono 16-bit silence, synthesized so no asset is needed.
    private static let silentWAV: Data = {
        let sampleRate = 8_000
        let dataSize = sampleRate * 2 // 16-bit mono
        var d = Data()
        func str(_ s: String) { d.append(contentsOf: s.utf8) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + dataSize)); str("WAVE")
        str("fmt "); u32(16); u16(1); u16(1)
        u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(dataSize))
        d.append(Data(count: dataSize))
        return d
    }()
}
#endif
