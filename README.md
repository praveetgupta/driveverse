# DriveVerse

A personal iOS app that shows real-time, time-synced lyrics for whatever is
currently playing in **Apple Music** or **Spotify**, surfaced on **CarPlay**
via a Live Activity (iOS 26 mirrors lock-screen Live Activities onto the
CarPlay screen). An in-app full-screen scrolling lyrics view exists for
passengers / parked use.

DriveVerse never plays audio and is **not** a CarPlay app (no CarPlay
entitlement, no CPTemplates) — the CarPlay surface is exclusively the Live
Activity.

> ⚠️ **Copyright / distribution note**
> Lyrics are fetched from the community-run [LRCLIB](https://lrclib.net) API
> for **personal use**. This is accepted community practice for private
> projects, but this app must **not** be distributed on the App Store without
> a licensed lyrics provider. Lyrics are cached locally only, for at most
> 30 days.

---

## How it works

```
Apple Music ──(MediaPlayer notifications + 1 s timer)──┐
                                                       ├─► NowPlayingCoordinator ─► SyncEngine ─► in-app lyrics view
Spotify ──(Web API poll, 5 s active / 15 s idle)───────┘        │                     │
                                                                ▼                     ▼
                                                       LRCLIB lyrics fetch    Live Activity (lock screen,
                                                       (cache-first, 30 d)    Dynamic Island, CarPlay)
```

- **Arbitration:** if Apple Music reports a playing item it wins (local,
  zero-latency, exact position). Otherwise a playing Spotify track wins. If
  both are idle, the last known track is kept, marked paused. You can pin a
  source in Settings.
- **Sync:** playback position is extrapolated between source reports
  (`position + (now − capturedAt)`) on a 500 ms tick; the current LRC line is
  found by binary search. Deviations > 2 s from the extrapolation are treated
  as seeks and snap immediately; smaller ones are polling jitter and ignored.
- **Live Activity updates** happen only when the current line index changes or
  play/pause flips — never on the tick — so a typical song is 40–80 local
  `Activity.update` calls.

## Requirements

- Xcode 26 (iOS 26 SDK), a free or paid Apple developer account for device
  signing.
- An iPhone on iOS 26 (Apple Music detection and Live Activities need real
  hardware).
- A Spotify account (free works) if you want Spotify detection.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you want to regenerate
  the project (`brew install xcodegen`). The generated
  `DriveVerse.xcodeproj` is checked in, so this is optional.

## Setup

### 1. Spotify app registration (once)

1. Go to <https://developer.spotify.com/dashboard> and create an app
   (Developer Mode is fine — it works for the account that owns the app).
2. Add this **Redirect URI**: `driveverse://callback`
3. Check **iOS** as the API/SDK you're using (Web API).
4. Copy the **Client ID** (no client secret is used — this is PKCE).

### 2. Local secrets

```bash
cp DriveVerse/Resources/Secrets.example.plist DriveVerse/Resources/Secrets.plist
# then edit Secrets.plist and paste your Spotify Client ID
```

`Secrets.plist` is gitignored; never commit it or hardcode the ID.

### 3. Build & run

```bash
open DriveVerse.xcodeproj
```

- Select the **DriveVerse** scheme, set your signing team on the `DriveVerse`
  and `DriveVerseWidgets` targets, and run on your iPhone.
- If you change the file layout, regenerate the project with
  `./scripts/generate.sh`.

### 4. Permissions on first launch

- **Media & Apple Music** access — required for Apple Music detection.
- **Live Activities** — enable for DriveVerse in Settings if prompted.

## Running the tests

- **In Xcode:** the `DriveVerseTests` target (Swift Testing) — `Cmd-U`.
- **From the command line** (works even with only Command Line Tools
  installed, via the SwiftPM harness in `Package.swift`):

```bash
./scripts/test.sh
```

The suite covers the LRC parser, title/artist normalization, sync
engine (extrapolation, seek snapping, line binary search), the LRCLIB client
fallback chain (stubbed with URLProtocol), the disk cache TTLs, PKCE (RFC 7636
test vector), the token refresh state machine, Spotify response parsing and
429/401 handling, source arbitration, and the Live Activity update policy.

## Using it in the car (CarPlay)

1. Connect the phone to CarPlay and start music in Apple Music or Spotify.
2. Open DriveVerse and toggle **Drive Mode** on.
3. When a track with synced lyrics plays, a Live Activity starts; iOS 26 shows
   it on the CarPlay screen (and the lock screen / Dynamic Island).

**Testing without a car:** Xcode → open the Simulator → **I/O → External
Displays → CarPlay** gives you a CarPlay Simulator window. Note that
MediaPlayer-based Apple Music detection doesn't work in the iOS Simulator, so
end-to-end testing is best on a real device; the CarPlay Simulator is mainly
useful for checking the Live Activity layout.

### Why Drive Mode exists (and its cost)

iOS suspends backgrounded apps, which would freeze polling and Live Activity
updates a few seconds after you switch to the music app or lock the phone.
Drive Mode keeps DriveVerse alive by playing a **silent, muted audio loop**
(`AVAudioSession` category `.playback` with `.mixWithOthers`, so it never
ducks or interrupts your music) via the `audio` background mode.

- It only runs while Drive Mode is toggled on **and** a lyrics Live Activity
  is active; it stops as soon as either ends.
- It costs some battery — that's why it's an explicit opt-in toggle.
- **App Store:** this technique is acceptable for a personally sideloaded
  build but would be rejected in App Review (silent audio to stay alive is
  explicitly disallowed). A store build would need a different approach
  (e.g. push-updated Live Activities from a server).

## Manual test checklists (real device)

### Apple Music detection (Phase 3)

- [ ] Fresh install prompts for Media & Apple Music access; granting it makes
      the Home card fill in when Apple Music plays.
- [ ] Play/pause in Apple Music flips the play indicator within ~1 s.
- [ ] Track skip changes the card and refetches lyrics.
- [ ] Seeking in Apple Music snaps the highlighted lyric line within ~1 s.
- [ ] Playing in Spotify instead: Apple Music source reports nothing and the
      card switches to the Spotify track (via polling).
- [ ] Denying media access shows the permission banner on Home instead of
      silently failing.

### Spotify (Phase 4)

- [ ] Connect Spotify completes in the in-app browser sheet and lands back in
      the app showing “Connected”.
- [ ] Playing in Spotify populates the card within one poll interval.
- [ ] Revoking the app at <https://www.spotify.com/account/apps/> makes the
      reconnect banner appear on the next poll.

### Live Activity + CarPlay (Phase 6)

- [ ] Starting a track with synced lyrics creates the Live Activity; lyric
      lines advance on time.
- [ ] Pausing shows the pause glyph; resuming continues. Stopping music ends
      the activity ~30 s later.
- [ ] Dynamic Island compact view shows the current line; long-press expands.
- [ ] With CarPlay connected, the activity appears on the car screen.

### Drive Mode (Phase 7)

- [ ] Toggle Drive Mode on with music playing → lock the phone → lyric lines
      keep advancing on the lock screen for whole songs.
- [ ] Toggle it off → app suspends normally in the background (updates stop
      after a while).
- [ ] Drive Mode audio never makes your music duck or stutter.
- [ ] Connect to CarPlay/Bluetooth with Drive Mode already on → lyrics keep
      advancing (the route change restarts the keep-alive).
- [ ] Invoke Siri or let an alarm fire mid-session → lyric updates resume
      within a couple of seconds after it ends.
- [ ] Lock the phone, wait 5+ minutes, switch songs from the lock screen →
      the Live Activity follows within ~1 s.
- [ ] Reopen the app after a long background stretch → the lyric line snaps
      to the correct position immediately (foreground resync).

## Known limitations

- **No CarPlay widget (stretch goal not shipped).** The iOS 26 CarPlay
  WidgetKit opt-in API was left out; the Live Activity covers the driving use
  case. Revisit `DriveVerseWidgets` if you want to add it.
- Without Drive Mode, background updates stop shortly after the app is
  suspended — foreground the app or use Drive Mode for long sessions.
- Spotify position is polled (3–10 s, configurable), so a seek in Spotify can
  take up to one interval to snap.
- The app can't seek playback (it's an observer) — the lyrics view is
  display-only by design.
- Tracks not on LRCLIB show “No lyrics found”; misses are re-checked after a
  day, hits are cached for 30 days.

## Project layout

Generated by XcodeGen from `project.yml`. `Package.swift` is a development
harness so the platform-independent core (everything under `DriveVerse/Core`,
plus the Live Activity update policy) builds and tests on macOS via
`swift test`; iOS-only code is fenced with `#if os(iOS)`.

```
DriveVerse/
├── App/                DriveVerseApp, AppModel (wiring)
├── Core/
│   ├── NowPlaying/     NowPlayingSource protocol, AppleMusicSource,
│   │                   SpotifySource, NowPlayingCoordinator (arbitration)
│   ├── Lyrics/         LRCParser, LyricsMatcher, LRCLIBClient,
│   │                   LyricsCache, LyricsService
│   ├── Sync/           SyncEngine (extrapolation + line index)
│   ├── Auth/           SpotifyAuth (PKCE, Keychain, refresh)
│   └── KeepAlive/      BackgroundKeeper (Drive Mode silent audio)
├── LiveActivity/       LyricsAttributes (shared with widget),
│                       LiveActivityController, update policy
├── Features/           Home, LyricsView, Settings (SwiftUI)
└── Resources/          Assets, Info.plist, Secrets(.example).plist
DriveVerseWidgets/      Live Activity UI (lock screen + Dynamic Island)
DriveVerseTests/        Swift Testing suite (also runs via ./scripts/test.sh)
```
