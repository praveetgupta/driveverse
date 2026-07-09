import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(AppModel.pollIntervalKey) private var pollInterval: Double = 5
    @State private var cacheCleared = false

    var body: some View {
        Form {
            Section {
                Picker("Preferred source", selection: pinBinding) {
                    ForEach(SourcePin.allCases) { pin in
                        Text(pin.displayName).tag(pin)
                    }
                }
            } header: {
                Text("Source")
            } footer: {
                Text("Automatic prefers Apple Music whenever it's playing (local, exact position), otherwise Spotify. Pin a source to ignore the other.")
            }

            Section {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Poll interval")
                        Spacer()
                        Text("\(Int(pollInterval)) s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $pollInterval, in: 3...10, step: 1)
                }
                if model.spotifyConnected {
                    Button("Disconnect Spotify", role: .destructive) {
                        model.disconnectSpotify()
                    }
                }
            } header: {
                Text("Spotify")
            } footer: {
                Text("How often DriveVerse asks Spotify what's playing. Lower is snappier; higher saves battery and API quota. Between reports, lyric timing is extrapolated locally.")
            }

            Section {
                Button("Clear lyrics cache") {
                    model.clearLyricsCache()
                    cacheCleared = true
                }
                if cacheCleared {
                    Label("Cache cleared", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            } header: {
                Text("Lyrics")
            } footer: {
                Text("Lyrics come from LRCLIB and are cached on this device for at most 30 days.")
            }

            Section {
                EmptyView()
            } header: {
                Text("Drive Mode & battery")
            } footer: {
                Text("Drive Mode keeps DriveVerse awake in the background by playing a silent, muted audio loop (mixed with your music, never audible). It uses extra battery, so it's opt-in and only runs while a lyrics Live Activity is on screen. This trick is fine for a personal sideloaded app but would not pass App Store review.")
            }

            Section {
                EmptyView()
            } header: {
                Text("About")
            } footer: {
                Text("DriveVerse is a personal-use app. Lyrics are fetched from the community-run LRCLIB API for private, non-commercial display. Do not distribute this app without a licensed lyrics provider.")
            }
        }
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var pinBinding: Binding<SourcePin> {
        Binding(get: { model.sourcePin }, set: { model.sourcePin = $0 })
    }
}
