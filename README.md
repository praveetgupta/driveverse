# DriveVerse

**Live, time-synced song lyrics on your car's CarPlay screen — for whatever you're already playing in Apple Music or Spotify.**

DriveVerse watches whatever song is playing, finds the synced lyrics for it, and shows the current line (plus the one coming up) right on your CarPlay display, lock screen, and Dynamic Island. You keep using Apple Music or Spotify exactly like you always do. DriveVerse just rides along and puts the words on screen.

It doesn't play any music of its own, it isn't a full CarPlay app, and it never touches your playback. It only reads what's playing and shows the lyrics.

Oh, and if you listen to Hindi, Punjabi, Russian, Japanese, or anything else that isn't written in the Latin alphabet, DriveVerse romanizes the lyrics so you can actually read along in English letters.

> **A note on lyrics and copyright.** Lyrics come from [LRCLIB](https://lrclib.net), a free community lyrics database. That's fine for a personal app you build and run yourself, which is exactly what this is. It is *not* okay for the App Store without a proper licensed lyrics provider, so please don't ship it there. Lyrics are cached only on your device, for 30 days at most.

---

## What it does

- **Reads your current song** from Apple Music (via the local MediaPlayer framework) or Spotify (via the Spotify Web API).
- **Fetches synced (LRC) lyrics** from LRCLIB and keeps them lined up with the music as it plays.
- **Shows the current + next line** as a Live Activity — the same tile appears on your **CarPlay** screen, **lock screen**, and **Dynamic Island** on iOS 26.
- **Romanizes non-English lyrics** into Latin letters on the device (Hindi, Cyrillic, Japanese, Korean, and more).
- **Keeps working while you drive** through a "Drive Mode" that stops iOS from freezing the app in your pocket.
- **A full-screen scrolling lyrics view** in the app itself, for passengers or when you're parked.

No account to make, no server, no analytics, no tracking. Everything happens on your phone.

## How it works

```
Apple Music ──(MediaPlayer, ~1s)──┐
                                  ├─► picks the active source ─► sync engine ─► lyrics on screen
Spotify ──────(Web API poll)──────┘         │                       │
                                            ▼                       ▼
                                   LRCLIB lyrics lookup     Live Activity
                                   (cached 30 days)         (CarPlay / lock screen / Dynamic Island)
```

A few details worth knowing:

- **Which source wins:** if Apple Music is playing, it's used (it's local and exact). Otherwise a playing Spotify track is used. You can also pin one source in Settings.
- **Staying in sync:** between updates, the app estimates the current playback position and finds the matching lyric line. If you skip or seek, it notices and snaps to the right line.
- **CarPlay:** iOS 26 automatically mirrors the lock-screen Live Activity onto the car screen. There's no CarPlay entitlement and no CPTemplate code here — the Live Activity *is* the CarPlay experience.

## Requirements

- An iPhone running **iOS 26** (Apple Music detection and Live Activities need real hardware — the Simulator can't do it).
- **Xcode 26** to build it.
- A free or paid Apple Developer account to sign the app onto your phone.
- A **Spotify** account only if you want Spotify support (Apple Music works without it).

## Setup

### 1. Get the code and open it

```bash
git clone https://github.com/praveetgupta/driveverse.git
cd driveverse
```

The Xcode project is checked in, so you can open `DriveVerse.xcodeproj` directly. (If you ever change which files exist, regenerate it with `./scripts/generate.sh`, which needs `brew install xcodegen`.)

### 2. Add your Spotify Client ID

Even if you don't use Spotify, you need this file to exist or the build won't compile:

```bash
cp DriveVerse/Resources/Secrets.example.plist DriveVerse/Resources/Secrets.plist
```

If you *do* want Spotify:

1. Go to the [Spotify Developer Dashboard](https://developer.spotify.com/dashboard) and create an app.
2. Add `driveverse://callback` as a **Redirect URI**.
3. Copy the **Client ID** (there's no client secret — this uses PKCE) into `Secrets.plist`.

`Secrets.plist` is gitignored, so your ID never gets committed. Keep it that way.

### 3. Sign and run

Open the project in Xcode, pick the **DriveVerse** scheme, and set your signing team on both the `DriveVerse` and `DriveVerseWidgets` targets (Signing & Capabilities tab). Plug in your iPhone and hit Run.

### 4. First-launch permissions

- **Media & Apple Music** — needed to see what Apple Music is playing.
- **Live Activities** — turn on **More Frequent Updates** under Settings → DriveVerse → Live Activities, or the lyrics stop updating after about 30 seconds in the background.
- **Location (While Using)** — asked the first time you turn on Drive Mode. It's how the app stays awake in the background (explained below). Say yes to the "Always" upgrade later only if you want the hands-free CarPlay automation.

## Using it in the car

1. Connect your phone to CarPlay and play something in Apple Music or Spotify.
2. Open DriveVerse and turn on **Drive Mode**.
3. When a song with synced lyrics plays, the lyrics tile shows up on the car screen (and your lock screen and Dynamic Island).

### Turn it on automatically when you get in

You don't have to open the app every time. DriveVerse includes two Shortcuts actions — **Start Drive Mode** and **Stop Drive Mode** — so your phone can do it for you:

1. Open the **Shortcuts** app → **Automation** → **+**.
2. Pick **CarPlay** → **Connects** → **Run Immediately** → add the **Start Drive Mode** action.
3. Make a second one: **CarPlay** → **Disconnects** → **Run Immediately** → **Stop Drive Mode**.

Now getting in the car starts DriveVerse in the background and puts up the lyrics tile on its own (it shows "♪ Waiting for music…" until you press play). Leaving the car shuts it all down so nothing keeps running in the background.

### Why Drive Mode needs to exist

iOS freezes apps a few seconds after you lock the phone or switch away, which would freeze the lyrics too. Drive Mode keeps DriveVerse running using a very low-power background location session (rough, city-block-level accuracy — the location is thrown away instantly and never stored or sent anywhere).

Why location and not the old "play silent audio" trick? Because iOS specifically blocks apps from updating Live Activities when the only reason they're awake is playing background audio. A location session is the same approach navigation apps use, and it's the one that actually lets the lyrics keep updating. It does use some battery, which is why Drive Mode is a manual toggle — and why the CarPlay automation above is handy, since it switches off the moment you leave.

## Privacy

Everything stays on your phone. There's no backend, no account, and no analytics.

- Song info is read locally (Apple Music) or from your own Spotify account over HTTPS.
- Only the basic track details (title, artist, album, length) are sent to LRCLIB to look up lyrics.
- Your Spotify login token is stored in the iOS Keychain.
- Lyrics are cached on disk for up to 30 days. Settings → Clear Cache wipes them.
- Drive Mode's location fixes are discarded immediately — nothing is saved or transmitted.
- Lyric romanization happens on the device. No text is sent anywhere for it.

## Running the tests

There's a full unit test suite (Swift Testing). In Xcode, press **Cmd-U**. From the command line:

```bash
./scripts/test.sh
```

It covers lyric parsing, title/artist matching, the sync engine, the LRCLIB client and its fallbacks, the on-disk cache, Spotify auth (PKCE, token refresh, response parsing), source arbitration, lyric romanization, and the Live Activity update logic.

## Good to know / limitations

- Without Drive Mode on, updates stop shortly after the app goes to the background. That's expected — Drive Mode is the fix.
- Spotify position is polled every few seconds, so a seek in Spotify can take a moment to catch up. Apple Music is instant.
- DriveVerse can't control playback (it's just watching), so the lyrics view is display-only by design.
- If a song isn't in LRCLIB, you'll see "No lyrics found." Misses are re-checked the next day; hits are cached.
- Romanization uses the standard system transliteration, which is very readable but occasionally a little literal.
- There's no dedicated CarPlay dashboard widget yet — the Live Activity covers the driving experience. It's a possible future addition.

## How the project is organized

```
DriveVerse/
├── App/            App entry point, Drive Mode shortcuts, and the main wiring
├── Core/
│   ├── NowPlaying/ Apple Music + Spotify sources and which one to trust
│   ├── Lyrics/     LRCLIB client, parser, matcher, cache, romanizer
│   ├── Sync/       Keeps the lyric line matched to the playback position
│   ├── Auth/       Spotify login (PKCE, Keychain, token refresh)
│   └── KeepAlive/  Drive Mode background location session
├── LiveActivity/   The lyrics tile shown on CarPlay / lock screen
├── Features/       Home, full-screen lyrics, Settings (SwiftUI)
└── Resources/      Assets, Info.plist, Secrets files
DriveVerseWidgets/  Live Activity + Dynamic Island UI
DriveVerseTests/    The test suite
```

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen). `Package.swift` is a helper so the core logic can be tested on a Mac without a device.

## Built with

Swift, SwiftUI, ActivityKit, WidgetKit, MediaPlayer, and Core Location. No third-party libraries. Lyrics by [LRCLIB](https://lrclib.net).

## License

The code is released under the [MIT License](LICENSE) — use it, fork it, learn from it. Note that this applies to the app's own code only, not to any song lyrics, which belong to their respective owners and are fetched from LRCLIB for personal use.
