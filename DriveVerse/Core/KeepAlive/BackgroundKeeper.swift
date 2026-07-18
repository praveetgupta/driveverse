import Foundation

#if os(iOS)
import AVFoundation

/// Keeps the app alive in the background during CarPlay sessions by looping a
/// silent buffer through AVAudioEngine. The session uses `.playback` with
/// `.mixWithOthers` so the real music (Apple Music / Spotify) is never ducked
/// or interrupted, and the mixer volume is zero.
///
/// ⚠️ App Store note (CLAUDE.md §6): a silent-audio keep-alive is fine for a
/// personally sideloaded build, but App Review rejects the `audio` background
/// mode when the app produces no audible content. A store build would need a
/// different strategy. That's why this runs only while the user has explicitly
/// toggled Drive Mode on AND a Live Activity is active — battery cost is opt-in.
final class BackgroundKeeper {
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private(set) var isRunning = false
    private var observers: [NSObjectProtocol] = []

    init() {
        buildEngine()
    }

    deinit {
        removeObservers()
    }

    func start() throws {
        guard !isRunning else { return }
        try activateAndPlay()
        isRunning = true
        installObservers()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        removeObservers()
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func buildEngine() {
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
    }

    private func activateAndPlay() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)

        // One second of silence — PCM buffers come zero-filled.
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100

        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
    }

    /// The engine dies silently in three ways, and each one suspends the app
    /// moments later unless the keep-alive restarts:
    /// - interruptions (Siri, calls, alarms) — resume on .ended;
    /// - output configuration changes — connecting to CarPlay/Bluetooth is
    ///   itself a route change that stops AVAudioEngine;
    /// - a media-services crash, which invalidates every audio object we
    ///   hold and requires rebuilding the engine from scratch.
    private func installObservers() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default

        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRunning else { return }
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { self.restart(rebuild: false) }
        })

        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.restart(rebuild: false)
        })

        observers.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRunning else { return }
            self.restart(rebuild: true)
        })
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }

    private func restart(rebuild: Bool) {
        player.stop()
        engine.stop()
        if rebuild { buildEngine() }
        try? activateAndPlay()
    }
}
#endif
