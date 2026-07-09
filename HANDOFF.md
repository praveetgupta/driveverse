# HANDOFF — continuing DriveVerse on a new machine

Context file for picking up development in a fresh Claude Code session
(the original session ran on a Mac without Xcode; this repo carries
everything it knew).

## Where things stand (2026-07-09)

- **All 8 build phases from CLAUDE.md are implemented.** Read `CLAUDE.md`
  (the spec, formerly `Claude.md`) and `README.md` first.
- **97 Swift Testing tests pass in 18 suites** — run `./scripts/test.sh`
  (works with full Xcode via plain `swift test` too; the script only adds
  framework paths needed on Command-Line-Tools-only machines).
- **The iOS targets have NEVER been compiled.** The original machine had no
  Xcode/iOS SDK, so all verification ran through the macOS SwiftPM harness
  (`Package.swift`), which compiles the whole app module with iOS-only code
  (`MediaPlayer`, `ActivityKit`, `AVAudioSession`, widget UI) fenced out via
  `#if os(iOS)`. Expect zero-to-a-few small compile errors in those fenced
  regions and in `DriveVerseWidgets/` on the first real build.

## First steps on this machine

```bash
# 1. Build for simulator (no signing needed)
xcodebuild -project DriveVerse.xcodeproj -scheme DriveVerse \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# 2. Run the test target the same way
xcodebuild -project DriveVerse.xcodeproj -scheme DriveVerse \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# 3. Fix whatever the iOS SDK flags (likely candidates: widget SwiftUI code,
#    LiveActivityController ActivityKit calls, AVAudioSession usage).
```

If files are added/moved, regenerate the project: `./scripts/generate.sh`
(needs `brew install xcodegen`).

## Human TODOs (not automatable)

1. **Signing for device runs:** Xcode → Settings → Accounts → add Apple ID;
   set the team on the `DriveVerse` and `DriveVerseWidgets` targets (or put
   `DEVELOPMENT_TEAM` in `project.yml` and regenerate). Simulator needs none.
2. **Spotify client ID:** create an app at developer.spotify.com/dashboard
   with redirect URI `driveverse://callback`, then
   `cp DriveVerse/Resources/Secrets.example.plist DriveVerse/Resources/Secrets.plist`
   and paste the ID. `Secrets.plist` is gitignored — never commit it.
3. **On-device verification:** walk the manual checklists in `README.md`
   (Apple Music detection, Spotify connect, Live Activity/CarPlay, Drive
   Mode). MediaPlayer and Live Activities need a real iPhone on iOS 26.

## Suggested first prompt for the new Claude Code session

> Read CLAUDE.md, README.md, and HANDOFF.md. All 8 phases are built and unit
> tests pass, but the iOS targets have never been compiled. Build the
> DriveVerse scheme for an iOS simulator, fix any compile errors without
> changing behavior, then run the DriveVerseTests target and get it green.

## Conventions this repo was built with

- Commits under the repo owner's name only — no AI/Co-Authored-By trailers.
- Xcode project is generated (XcodeGen, `project.yml` is the source of truth).
- No third-party packages; MediaPlayer not MusicKit; LRCLIB only; Live
  Activity updates only on line change or play/pause flip (see
  `LiveActivityUpdatePolicy` and its tests).
- Delete this file once the iOS build + device verification are done.
