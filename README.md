# CapDeck

CapDeck is a lightweight native macOS screenshot app designed around one fast
workflow:

```text
Capture -> Clipboard -> Paste -> Done
```

It is built for screenshots that are often temporary and immediately pasted
into ChatGPT, Codex, Claude, Gemini, Messenger, Slack, Discord, or documentation.

## Status

CapDeck V1.2.2 has a complete personal native capture, clipboard, preview,
saving, annotation, and session-history workflow. The V1 engineering scope is
100% complete as of 2026-07-14. Three external compatibility checks have been
handed off for owner review because they require external paste destinations,
physical display changes, or additional macOS hardware. See the
[implementation status](STATUS.md) for the current breakdown and verification
snapshot.

## MVP

- Region, window, and full-screen capture
- Multi-monitor and Retina support
- Automatic clipboard copy
- Never Save, Always Save, and Ask Every Time policies
- Always, Never, and Auto Hide previews
- Configurable shortcuts, destination, filename, format, and delay
- Basic crop, arrow, rectangle, text, blur, undo, and redo tools
- Native menu bar and settings experience, including signed update checks
- Session-only bounded Capture History with explicit cleanup

## Technology

Swift 6, SwiftUI, AppKit, ScreenCaptureKit, CoreGraphics, CoreImage, and Swift
Package Manager. The app is local-first, sandboxed, requires no account, and
currently targets macOS 14 or later.

## Repository Layout

```text
CapDeck/
├── PROJECT_OVERVIEW.md
├── PRODUCT_REQUIREMENTS.md
├── ARCHITECTURE.md
├── CODING_GUIDELINES.md
├── TASKS.md
├── README.md
├── CapDeck.xcodeproj
├── CapDeck/
├── CapDeckTests/
└── CapDeckUITests/
```

The test target directories are retained alongside the requested core layout so
the generated Xcode project remains buildable and testable.

## Documentation

- [Project overview](PROJECT_OVERVIEW.md)
- [Product requirements](PRODUCT_REQUIREMENTS.md)
- [Architecture](ARCHITECTURE.md)
- [Coding guidelines](CODING_GUIDELINES.md)
- [Tasks and roadmap](TASKS.md)
- [Implementation status](STATUS.md)
- [Capture and preview acceptance](ACCEPTANCE.md)

## Build

1. Open `CapDeck.xcodeproj` in Xcode.
2. Select the `CapDeck` scheme.
3. Choose a local Mac destination.
4. Build and run, then click the transparent `CapDeck` mark in the menu bar.
5. Choose **Capture Region**, **Capture Window**, or **Capture Full Screen**.

The default global shortcuts work while another app is active:

- `Control + Shift + J` — Capture Region
- `Control + Shift + K` — Capture Window
- `Control + Shift + L` — Capture Full Screen
- `Control + Shift + 9` — Capture History

These defaults intentionally avoid the built-in macOS `Command + Shift`
screenshot shortcuts. CapDeck does not require Accessibility permission for
global shortcuts. Click a shortcut in Settings and press a new key combination
to customize it; CapDeck preserves the previous working shortcut if the new one
cannot be registered.

Region selection dims every connected display, shows the selected pixel size,
and supports Escape cancellation. Full-screen capture from the menu asks you to
click the target display; the global shortcut captures the display under the
pointer. Captures are exported at each display's native pixel density without
interpolation or artificial enlargement. A capture delay of zero, three, or
five seconds is available from the menu and Settings.

After capture, Preview can be set to Always, Never, or Auto Hide. A compact,
non-activating thumbnail appears at the bottom-right of the display that was
captured, following the native macOS screenshot flow. Clicking it opens the
full preview on that display. The full preview reports the exact source pixel
dimensions and defaults to Fit so the whole composition is immediately visible,
with physical-pixel 1:1 available for close inspection. Preview scaling never
changes the PNG stored on the clipboard. The full preview also provides Copy
and Save As controls. A successful Copy or Save closes Preview automatically;
cancellation and failure keep it open for retry. Choose Annotate to open the native editor. Its first
vertical slice supports Rectangle drawing, Undo/Redo, and Copy Annotated while
retaining the original pixel dimensions and source capture.

Saving can be configured in Settings:

- **Never** keeps the clipboard-first workflow and creates no file.
- **Always** writes each capture to the selected folder.
- **Ask Every Time** opens the native macOS Save panel after each capture.

PNG and JPEG are supported. JPEG quality is configurable, while both formats
retain the capture's original pixel dimensions. Filenames accept `{date}`,
`{time}`, and `{timestamp}` tokens. Existing files are never overwritten;
CapDeck appends `-2`, `-3`, and so on when a name is already in use. A save error
does not remove the clipboard image or prevent Preview from opening.

Settings are organized into native General, Capture, Shortcuts, and After
Capture tabs. General includes **Check for Updates** and an opt-in automatic
check preference. Update checks use a signed Sparkle feed and signed release
archives; CapDeck does not send capture content or a system profile. The AI
Workflow preset enables Auto Copy, Never Save, and a two-second preview in one
action. Launch at Login uses macOS Service Management; local ad-hoc builds
report that an Apple Developer-signed build is required instead of presenting a
non-working toggle.

Capture History keeps at most 10 recent captures and approximately 256 MiB of
pixel data in RAM. It writes no hidden history files, can be cleared at any
time, and is released completely when CapDeck quits.

The first capture asks for macOS Screen Recording permission. If access was
previously denied, use **Open Screen Recording Settings…** from the CapDeck menu
and relaunch the app after granting access. If permission is revoked while a
capture is already starting, CapDeck returns to the same recovery path instead
of continuing with clipboard, save, or preview actions.

CapDeck uses the bundle identifier `com.jesdx.capdeck`. A previous installation
under another app identity does not transfer Screen Recording permission or
settings automatically; grant CapDeck access once and configure its new clean
profile normally.

Run the unit tests from Xcode or with:

```sh
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck \
  -destination 'platform=macOS' -only-testing:CapDeckTests test
```

Build the local V1.2.2 release archive with:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  Scripts/build-release.sh
```

Set `CAPDECK_SIGNING_IDENTITY` to a Developer ID Application identity when one
is available. Without it, the script produces an ad-hoc signed local build and
adds the library-validation exception required for an ad-hoc host to load
Sparkle. Developer ID builds do not receive that exception.

After building, prepare the signed Sparkle appcast and release payload with:

```sh
Scripts/prepare-update.sh
```

The signing key stays in the macOS Keychain. Only the public EdDSA key is
embedded in the app. Public distribution still requires a Developer ID and
notarization for a normal Gatekeeper experience.

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to
build, test, and open a pull request, and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
for community expectations.

Note on updates: the Sparkle feed (`SUFeedURL`) and public EdDSA key
(`SUPublicEDKey`) in `CapDeck/Info.plist` point at this project's own release
channel. If you fork CapDeck and want working self-updates, replace them with
your own feed and signing key. Local builds work without any signing key — see
the build instructions above.

## License

CapDeck is released under the [MIT License](LICENSE).
