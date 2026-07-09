import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NowPlayingCard()
                    LyricPreviewCard()
                    SpotifySection()
                    DriveModeCard()
                    if model.appleMusicAuth == .denied {
                        InfoBanner(
                            symbol: "exclamationmark.triangle",
                            text: "Apple Music detection is off. Allow Media & Apple Music access in Settings → DriveVerse."
                        )
                    }
                    if let message = model.errorMessage {
                        InfoBanner(symbol: "xmark.octagon", text: message)
                    }
                }
                .padding()
            }
            .navigationTitle("DriveVerse")
            .toolbar {
                NavigationLink {
                    SettingsView()
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .task { model.start() }
    }
}

// MARK: - Now playing

private struct NowPlayingCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let state = model.nowPlaying {
                HStack {
                    SourceBadge(source: state.source)
                    Spacer()
                    Image(systemName: state.isPlaying ? "play.fill" : "pause.fill")
                        .foregroundStyle(.secondary)
                }
                Text(state.title)
                    .font(.title2.bold())
                    .lineLimit(2)
                Text(state.artist)
                    .foregroundStyle(.secondary)
                if let position = model.position, state.durationMs != nil {
                    ProgressView(value: position.trackProgress)
                        .tint(.accentColor)
                }
            } else {
                Label("Nothing playing", systemImage: "music.note")
                    .foregroundStyle(.secondary)
                Text("Start a song in Apple Music or Spotify — DriveVerse picks it up automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SourceBadge: View {
    let source: MusicSource

    var body: some View {
        Text(source.displayName)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(source == .spotify ? .green.opacity(0.25) : .pink.opacity(0.25),
                        in: Capsule())
    }
}

// MARK: - Lyrics preview → full screen

private struct LyricPreviewCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationLink {
            LyricsScreen()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label("Lyrics", systemImage: "quote.opening")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                switch model.lyricsState {
                case .idle:
                    Text("Lyrics show up here").foregroundStyle(.secondary)
                case .loading:
                    Text("Finding lyrics…").foregroundStyle(.secondary)
                case .synced:
                    Text(model.position?.currentLine ?? "♪")
                        .font(.headline)
                        .lineLimit(2)
                    if let next = model.position?.nextLine {
                        Text(next)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                case .plain:
                    Text("Lyrics available (not synced)").font(.headline)
                case .instrumental:
                    Text("Instrumental 🎶").foregroundStyle(.secondary)
                case .notFound:
                    Text("No lyrics found").foregroundStyle(.secondary)
                case .failed:
                    Text("Couldn't load lyrics").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Spotify

private struct SpotifySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Spotify", systemImage: "music.note.tv")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            if !model.spotifyAuth.hasClientID {
                Text("Add your Spotify client ID: copy Secrets.example.plist to Secrets.plist and paste the ID from developer.spotify.com. See README.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if model.spotifyNeedsReconnect {
                InfoBanner(symbol: "exclamationmark.triangle",
                           text: "Spotify session expired.")
                connectButton(title: "Reconnect Spotify")
            } else if model.spotifyConnected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                connectButton(title: "Connect Spotify")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }

    private func connectButton(title: String) -> some View {
        Button {
#if os(iOS)
            Task { await model.connectSpotify() }
#endif
        } label: {
            Text(title)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
    }
}

// MARK: - Drive Mode

private struct DriveModeCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $model.driveMode) {
                Label("Drive Mode", systemImage: "car.fill")
                    .font(.headline)
            }
            Text("Keeps lyrics updating in the background for CarPlay. Uses a little more battery — turn it on only while driving.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Shared bits

struct InfoBanner: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
    }
}
