# DRIVEVERSE — Build Specification for Claude Code

A personal iOS app that shows real-time, time-synced lyrics for whatever is currently playing in Apple Music OR Spotify, surfaced on CarPlay via a Live Activity (iOS 26 shows Live Activities on the CarPlay screen).

Read this entire file before writing code. Build phase by phase. Run each phase's checks before moving on. This is a personal-use app, not an App Store submission — noted where that changes decisions.

---

## 1. Product summary

The user plays music normally in the Apple Music app or the Spotify app. DriveVerse runs alongside, detects the current track and playback position, fetches time-synced lyrics from LRCLIB, and renders the current + next lyric line in a Live Activity (lock screen, Dynamic Island, and CarPlay). An in-app full-screen scrolling lyrics view exists for passengers/parked use.

This is NOT a CarPlay app. Do not request any CarPlay entitlement, do not use CPTemplate APIs. The CarPlay surface is exclusively the Live Activity (and optionally an iOS 26 CarPlay-capable widget as a stretch goal).

---

## 2. Hard constraints

1. **No audio playback.** DriveVerse never plays music. It observes playback from other apps.
2. **Apple Music detection** uses the MediaPlayer framework: `MPMusicPlayerController.systemMusicPlayer`, `nowPlayingItem`, `currentPlaybackTime`, `playbackState`, and `MPMusicPlayerControllerNowPlayingItemDidChangeNotification` / `playbackStateDidChangeNotification`. Requires `NSAppleMusicUsageDescription` and media library authorization. Do NOT use MusicKit developer tokens for this — not needed.
3. **Spotify detection** uses the Spotify Web API from the app directly: Authorization Code Flow **with PKCE** (client ID only, no secret, redirect via custom URL scheme `driveverse://callback`). Poll `GET /v1/me/player/currently-playing` while active. Assume Developer Mode (works for the account owner). Scopes: `user-read-currently-playing user-read-playback-state`.
4. **Lyrics** come from the LRCLIB public API (`https://lrclib.net/api/get` with `track_name`, `artist_name`, `album_name`, `duration` query params; fallback `https://lrclib.net/api/search`). No API key. Send a descriptive `User-Agent` header (`DriveVerse/1.0 personal project`) per LRCLIB's request. Prefer `syncedLyrics` (LRC format); fall back to `plainLyrics` (display without highlighting); handle instrumental (`instrumental: true`) and not-found.
5. **Copyright note:** lyrics display for personal use via LRCLIB is the accepted community practice, but this app must not be distributed on the App Store without a licensed lyrics provider. Add this note to the README. Do not cache lyrics longer than 30 days; store cache locally only.
6. **Live Activity updates** are performed locally via ActivityKit (`Activity.update`). Design the ContentState to be tiny (current line, next line, progress fraction, source badge). Do not attempt push-based updates.
7. Minimum deployment target: iOS 26. Swift 5.10+, SwiftUI, no third-party packages.
8. Never hardcode the Spotify client ID; read it from an `xcconfig` / `Secrets.plist` excluded via `.gitignore`, with a `Secrets.example.plist` committed.

---

## 3. Project layout

```
driveverse/
├── CLAUDE.md
├── README.md
├── DriveVerse.xcodeproj (generate via XcodeGen project.yml if xcodegen available; otherwise create the .xcodeproj structure directly)
├── DriveVerse/
│   ├── App/DriveVerseApp.swift
│   ├── Core/
│   │   ├── NowPlaying/
│   │   │   ├── NowPlayingSource.swift        # protocol
│   │   │   ├── AppleMusicSource.swift
│   │   │   ├── SpotifySource.swift
│   │   │   └── NowPlayingCoordinator.swift   # picks active source
│   │   ├── Lyrics/
│   │   │   ├── LRCLIBClient.swift
│   │   │   ├── LRCParser.swift               # pure, unit-tested
│   │   │   ├── LyricsCache.swift             # disk cache keyed by track signature
│   │   │   └── LyricsMatcher.swift           # title/artist normalization
│   │   ├── Sync/SyncEngine.swift             # position extrapolation + current line index
│   │   ├── Auth/SpotifyAuth.swift            # PKCE, Keychain token storage, refresh
│   │   └── KeepAlive/BackgroundKeeper.swift  # see §6
│   ├── LiveActivity/
│   │   ├── LyricsAttributes.swift            # shared with widget extension
│   │   └── LiveActivityController.swift
│   ├── Features/
│   │   ├── Home/                             # status, source indicator, connect Spotify
│   │   ├── LyricsView/                       # full-screen synced scroll view
│   │   └── Settings/                         # source priority, polling interval, cache clear
│   └── Resources/
├── DriveVerseWidgets/                        # widget extension target
│   ├── LyricsLiveActivity.swift              # ActivityConfiguration + Dynamic Island
│   └── (stretch) CarPlayLyricsWidget.swift
└── DriveVerseTests/
```

---

## 4. Core design

### 4.1 NowPlayingSource protocol
```swift
struct NowPlayingState: Equatable {
    let title: String; let artist: String; let album: String?
    let durationMs: Int?; let positionMs: Int
    let isPlaying: Bool; let source: MusicSource   // .appleMusic | .spotify
    let capturedAt: Date                            // for extrapolation
}
protocol NowPlayingSource {
    var statePublisher: AnyPublisher<NowPlayingState?, Never> { get }
    func start(); func stop()
}
```

### 4.2 AppleMusicSource
Subscribe to the two MediaPlayer notifications, call `beginGeneratingPlaybackNotifications()`. On each event and on a 1 s timer while playing, emit state from `nowPlayingItem` + `currentPlaybackTime`. Handle nil `nowPlayingItem` (e.g. Spotify is the one playing) by emitting nil.

### 4.3 SpotifySource
Poll `currently-playing` every 5 s while the coordinator says Spotify is the active source (poll every 15 s when idle-probing). Parse `progress_ms`, `is_playing`, `item.name`, `item.artists[0].name`, `item.album.name`, `item.duration_ms`. On 401, refresh token; on refresh failure, surface a reconnect banner. On 429, respect `Retry-After`.

### 4.4 NowPlayingCoordinator (source arbitration)
Rule: if AppleMusicSource reports an item AND `isPlaying`, Apple Music wins (it is local, zero-latency, exact position). Otherwise, if Spotify reports `is_playing`, Spotify wins. If both idle, keep last known with `isPlaying = false`. User can pin a source in Settings.

### 4.5 SyncEngine
Position at render time = `positionMs + (now − capturedAt)` when playing (extrapolation matters for Spotify's 5 s polls). Tick on a 500 ms timer. Binary-search the parsed LRC line timestamps for the current index. Expose `(currentLine, nextLine, lineProgress)`. On track change: cancel, fetch lyrics (cache first), restart. Detect seeks: if reported position deviates from extrapolated by >2 s, snap.

### 4.6 LRCParser (pure function, heavily tested)
Parse `[mm:ss.xx]` tags including multiple tags per line, ignore metadata tags (`[ar:]`, `[ti:]`, `[offset:]` — apply offset if present), sort by time, strip empty lines. Output `[(timeMs: Int, text: String)]`.

### 4.7 LyricsMatcher
Normalize before querying LRCLIB: lowercase, strip parenthetical suffixes ("(Remastered 2011)", "- Radio Edit"), strip "feat./ft." clauses from artist and title, trim. Query `/api/get` with duration; if 404, retry `/api/get` without album; if still 404, use `/api/search` and pick the result whose duration is within ±3 s and normalized title matches. If nothing: show "No lyrics found" state.

---

## 5. Live Activity

- `LyricsAttributes`: fixed = track title, artist, source. `ContentState`: `currentLine`, `nextLine`, `progress` (0–1 through track), `isPlaying`.
- Start the activity when playback of a track with lyrics begins; end it 30 s after playback stops or when the app is terminated.
- Update policy: only call `Activity.update` when the current line index changes or play/pause flips — NOT on every 500 ms tick. Typical song = 40–80 updates over 3–4 minutes; acceptable locally.
- Lock screen view: title/artist small, current line large (2-line max, `.title2` bold), next line dimmed. Dynamic Island: compact = music note + marquee current line; expanded = same as lock screen.
- CarPlay renders the lock-screen Live Activity presentation automatically on iOS 26 — no extra code, but keep the layout legible at small sizes: high contrast, no more than two text rows plus progress.
- Info.plist: `NSSupportsLiveActivities = YES` in the app target.

**Stretch (build last, behind a feature flag):** an iOS 26 CarPlay-capable WidgetKit widget showing the current line. The CarPlay widget opt-in API is new — consult current Apple documentation for the exact WidgetKit configuration rather than guessing; if unclear, ship without it and note it in README.

---

## 6. Background keep-alive (personal-use decision)

iOS will suspend the app, killing polling and Live Activity updates. Strategy, in order:
1. Foreground-first UX: the in-app lyrics view is the primary surface; Live Activity keeps working while the app is foregrounded or briefly backgrounded.
2. For CarPlay sessions, implement `BackgroundKeeper`: an `AVAudioSession` (category `.playback`, `mixWithOthers`) playing a silent looping buffer via `AVAudioEngine`, started only when the user toggles "Drive Mode" and a Live Activity is active; stopped when Drive Mode ends. Requires the `audio` background mode capability.
3. Document clearly in README and a code comment: the silent-audio keep-alive is fine for a personally sideloaded app but would be rejected on App Store review; the App Store path would need a different approach.
Make Drive Mode an explicit user toggle (big button on Home + a toggle in the Live Activity is not possible — keep it in-app) so battery cost is opt-in.

---

## 7. Build order and acceptance criteria

**Phase 0 — Scaffold.** Project generates and builds (`xcodebuild -scheme DriveVerse -destination 'generic/platform=iOS' build` or simulator destination). App target + widget extension target + test target. Empty Home screen runs. ✓ Build succeeds, one placeholder test passes.

**Phase 1 — LRC parsing + matching (pure logic first).** `LRCParser`, `LyricsMatcher`, `SyncEngine` with injected clock. ✓ Unit tests: multi-tag lines, offset tag, out-of-order timestamps, seek snapping, extrapolation accuracy, normalization cases ("Song (feat. X) - Remix" → "song").

**Phase 2 — LRCLIB client + cache.** URLSession client with User-Agent, get→get-without-album→search fallback chain, disk cache (30-day TTL, track-signature key = normalized title|artist|duration-bucket). ✓ Tests with stubbed URLProtocol: hit, fallback chain, instrumental, 404, cache round-trip.

**Phase 3 — Apple Music source.** Authorization request flow, notification subscriptions, 1 s position timer, nil handling. ✓ Manual test checklist in README (needs a real device); unit-test the state mapping with fakes.

**Phase 4 — Spotify source.** PKCE auth via `ASWebAuthenticationSession`, Keychain storage, refresh, polling with backoff, 429 handling. ✓ Tests: PKCE verifier/challenge generation vectors, token refresh state machine, response parsing fixtures.

**Phase 5 — Coordinator + full-screen lyrics UI.** Source arbitration, Home screen (now playing card, source badge, Connect Spotify button, Drive Mode toggle), scrolling synced lyrics view with auto-scroll + tap-to-scrub disabled (observer app can't seek — display only). ✓ Arbitration unit tests (AM playing beats Spotify; pinning works).

**Phase 6 — Live Activity + Dynamic Island.** Attributes, controller lifecycle, update-on-line-change policy, widget extension UI. ✓ Builds; update-policy unit test (feed synthetic line changes, assert update count equals line changes, not ticks).

**Phase 7 — Drive Mode keep-alive.** BackgroundKeeper with silent engine, capability wiring, opt-in toggle, battery note in Settings. ✓ Code-reviewed against §6; manual device checklist added to README.

**Phase 8 — Polish.** App icon placeholder, error/empty states (no lyrics, Spotify disconnected, no permission), Settings (source pin, poll interval 3–10 s, clear cache), README: setup (Spotify app registration with custom scheme redirect, signing, CarPlay testing steps via CarPlay Simulator in Xcode: I/O → External Displays → CarPlay), known limitations, copyright note from §2.5.

---

## 8. Do NOT

- Do not add CarPlay framework code, CPTemplates, or CarPlay entitlements.
- Do not use MusicKit or an Apple developer token — MediaPlayer framework only.
- Do not implement audio playback of music, previews, or streams.
- Do not add Genius/Musixmatch scraping. LRCLIB only.
- Do not update the Live Activity on a fixed timer — only on line change or state flip.
- Do not add accounts, analytics, or a backend. This app is fully client-side.
