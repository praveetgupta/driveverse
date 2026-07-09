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
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private(set) var isRunning = false

    init() {
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0
    }

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)

        // One second of silence — PCM buffers come zero-filled.
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100

        try engine.start()
        player.scheduleBuffer(buffer, at: nil, options: .loops)
        player.play()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isRunning = false
    }
}
#endif
