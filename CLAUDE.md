# MiniDeck: notes for working on it

A floating mini player for Apple Music on macOS that controls Music.app through AppleScript and Apple Events.
User-facing docs are in `README.md`. This file covers how to build, test and release, and the traps found so far
(up to 0.29, 2026-11-28).

## Build

- Swift Package Manager. Only the **Command Line Tools** are installed on the dev Mac (no Xcode).
  - SwiftUI's `@State` (and other macro-based property wrappers) **don't compile** there: the macro plugin is
    missing. Keep view state in the `PlayerModel` ObservableObject and pass `Binding(get:set:)`.
  - `@Binding` in an `NSViewRepresentable` works.
- `swift build` is a quick compile check. `./build.sh` makes the real app: arm64 and x86_64 built separately
  (`--scratch-path .build-arm64` / `.build-x86`), joined with `lipo`, ad-hoc signed, bundle id `local.minideck`,
  version from `VERSION`. It leaves `MiniDeck.app` and `dist/MiniDeck.zip`; `--install` copies to `~/Applications`.
  - Binaries are found with `swift build --show-bin-path`, because the output folder differs between Swift versions.
- The user runs MiniDeck from `/Applications`. To test a build locally:
  `pkill -x MiniDeck; rm -rf /Applications/MiniDeck.app && cp -R MiniDeck.app /Applications/ && open /Applications/MiniDeck.app`.

## Release

- `./release.sh X.Y "notes"`:
  - checks for a clean tree on `main`;
  - writes `VERSION` and commits it;
  - makes an annotated tag (its message becomes the release notes), pushes, then follows the CI run.
- `.github/workflows/build.yml`:
  - runner `macos-26`, newest `/Applications/Xcode_26.*`, fails if the SDK is below 26 (Liquid Glass needs it);
  - builds with one retry, then checks both architectures, `NSGlassEffectView`, the version and the signature;
  - uploads the artifact; on a `v*` tag, publishes the release with `MiniDeck-X.Y.zip` and a plain `MiniDeck.zip`
    (the README's terminal install uses `releases/latest/download/MiniDeck.zip`).
  - `paths-ignore` skips docs, `*.md` and `VERSION`.
- `rerun-once.yml` re-runs a failed Build once (macOS arm64 runners sometimes aren't available:
  "job was not acquired by Runner").
- Pushing workflow files needs the gh token's `workflow` scope (`gh auth refresh -h github.com -s workflow`). The
  repo's credential helper is reset to only `!gh auth git-credential`, because a global osxkeychain helper held a
  stale token.
- Only release when the user asks ("release it"). Otherwise commit and push to `main`.

## Code map

- `MusicBridge.swift`:
  - all Music access: compiled NSAppleScripts cached and run on one serial queue (NSAppleScript isn't thread-safe);
  - transport buttons send raw Apple Events (`hookPlPs` / `hookNext` / `hookPrev`) so they never wait behind a slow query;
  - `status` returns 11 `|`-separated fields (the last is Music's `sound volume`);
  - `cue(trackID:playlistID:position:thenPlay:)`: see the queue section below.
- `PlayerModel.swift`:
  - state; polling (1 s tick timer, polls every 5 s while playing and visible, 15 s otherwise); Music's
    `com.apple.Music.playerInfo` distributed notification for instant updates;
  - resume (saved in UserDefaults on quit and every 10 s), volume, the playlist-picker state;
  - `enum Fuzzy` (subsequence match that scores word starts and runs, ignores case and accents).
- `PlayerView.swift`:
  - the player; the volume popover; the playlist picker popover; the right-click menu;
  - `ScrollCatcher` (scroll over the volume icon);
  - `SearchField` (an NSSearchField wrapper that handles arrows, Return and Esc).
- `TrackListView.swift`: the song list. `main.swift`: the borderless non-activating `NSPanel`, app menu, occlusion
  tracking. `About.swift`: the standard About panel. `Log.swift`: `~/Library/Logs/MiniDeck.log`.

## Traps (all found the hard way)

- **Queue:** AppleScript `play <track>` gives Music a **one-song queue**, even as `tell playlist to play track N` or
  while that playlist is already playing, so "next" goes nowhere. Only `play <playlist>` queues the rest.
  - To start mid-playlist, `cue`:
    1. mutes Music and turns shuffle off;
    2. plays the playlist, then sends `next track` until the wanted persistent ID is current, waiting for each skip to
       land (~0.35 s a song; fast `next` loops get ignored);
    3. seeks, pauses, and restores the volume and shuffle.
  - It gives up after 25 s and plays the single song instead. Music doesn't restore its own queue after a relaunch.
- **AppleScript reserved words** in Music's dictionary: `st`, `before`. Prefix script variables with `md`. When
  changing a script, check it with `osacompile`, and make sure error paths restore Music's volume.
- **Startup:** Music sends Paused/Stopped notifications while launching. `apply()` ignores notifications while
  `loadingText` is set, or the UI flashes "Not playing".
- **Popovers must not change size while open**: resizing one while typing crashed AppKit (`NSPopoverFrame
  setFrameSize` during a constraints pass). The playlist picker has a fixed size.
- **Non-activating panel**: to type into a popover, call `NSApp.activate` and make the field first responder.
- **Unsigned builds on a company-managed Mac:** a browser-downloaded copy can freeze at launch (main thread stuck at
  `_dyld_start`, no log line, no crash report) because endpoint security holds new unsigned binaries. Removing the
  quarantine flag afterwards didn't help, but a copy fetched with `curl` (no quarantine) ran. Hence the terminal
  install in the README. Real fix: Developer ID signing plus notarization (not done; needs a paid account).

## Testing the UI without a person

- Find the window: CGWindowList, owner `MiniDeck`. The player is about 360×140 pt; popovers are separate windows.
- Capture one window with `screencapture -x -o -l <windowID>`. Glass windows look flat grey that way; for README
  shots, capture the screen region (`screencapture -R`) and use a window capture's alpha as a mask.
- Synthetic clicks and typing with CGEvent work. Check that MiniDeck is the front app before typing, so keystrokes
  can't land in another app. Universal Control can take the mouse away.
- Opening the About panel via System Events: `click menu item "About MiniDeck" of menu 1 of menu bar item "MiniDeck"
  of menu bar 1` of process "MiniDeck".
- Most behaviour is visible in `~/Library/Logs/MiniDeck.log`: status lines, notifications, `resume: queue|single`.

## Ideas not done yet

Repeat button, media keys / shortcuts, compact mode, album art in the song list, a shorter startup spinner
(about 14 s cold: Music launch plus cue), Developer ID signing and notarization, a Homebrew cask.
