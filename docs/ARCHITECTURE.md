# CapDeck Architecture

## 1. Architecture Goals

The architecture prioritizes a short capture-to-clipboard path, deterministic
post-capture behavior, native macOS integration, and replaceable feature
boundaries. The initial implementation should stay small and avoid persistent
infrastructure that is not yet required.

The current minimum deployment target is macOS 14 because the capture slice
uses `SCScreenshotManager`. App Sandbox remains enabled. Custom save folders
use user-selected read/write access with a persisted security-scoped bookmark.

## 2. High-Level Design

CapDeck uses a feature-oriented application layer over focused system services
and native presenters:

```text
Menu bar / shortcuts / settings
              |
              v
      Capture Coordinator
       /      |       \
Selection  Capture   Permission
              |
              v
       Capture Result
       /      |       \
Clipboard   Save     Preview/Editor
                       |
                     History
```

`CaptureCoordinator` owns workflow sequencing. System services perform one kind
of external interaction and do not decide product policy. Feature presenters
own CapDeck's native AppKit panels and overlays; they translate UI interaction
into their protocol dependencies but do not own capture or save policy.

A service may show a platform-required system panel as part of its capability
boundary (for example, `NSSavePanel` in the file service). Custom CapDeck UI
always belongs to a feature presenter instead.

Annotation and History are implemented MVP boundaries. History deliberately
remains session-only rather than introducing a persistence database.

## 3. Source Layout

```text
CapDeck/
├── App/
├── Models/
├── Features/
│   ├── Capture/
│   ├── Selection/           # Geometry + selection overlay presenter
│   ├── Settings/
│   ├── MenuBar/
│   ├── Preview/             # Native preview panel presenter
│   ├── Annotation/          # Document + native editor presenter
│   ├── History/             # Store + native history panel presenter
│   └── TextRecognition/     # CaptureTextCopier: OCR → clipboard workflow
├── Services/
│   ├── CaptureService/
│   ├── ClipboardService/
│   ├── DisplayService/
│   ├── FileService/
│   ├── LaunchAtLoginService/
│   ├── PermissionService/
│   ├── ShortcutService/
│   ├── TextRecognitionService/ # Vision VNRecognizeTextRequest boundary
│   └── UpdateService/
└── Assets.xcassets/
```

Create folders when the first real type needs them; avoid empty architecture
scaffolding. Xcode's file-system-synchronized group will reflect source folders
from disk.

## 4. Core Models

Suggested value types:

- `CaptureMode`: region, window, or display.
- `CaptureRequest`: mode, target, delay, and applicable options.
- `CaptureResult`: image data/representation, pixel size, scale, timestamp, and
  capture metadata.
- `SavePolicy`: never, always, or askEveryTime.
- `PreviewPolicy`: always, never, or autoHide(duration).
- `ImageFormat`: png or jpeg with format-specific options.
- `AppSettings`: persisted user preferences composed from smaller setting types.

The canonical capture result should remain in memory through the post-capture
pipeline. Clipboard and file encoders may derive representations from it without
recapturing the screen.

## 5. Components

### App Layer

Owns application lifecycle, menu bar scenes, settings windows, dependency
construction, and launch-at-login behavior. The implemented login-item boundary
uses `SMAppService.mainApp` and exposes enabled, approval-required, and
unavailable states. It wires concrete services and feature presenters into
feature coordinators.

### Capture Feature

`CaptureCoordinator` validates permission, applies delay, invokes selection when
needed, requests capture, and dispatches the successful result to the
post-capture pipeline. It exposes explicit idle, preparing, selecting,
capturing, processing, completed, cancelled, and failed states.

### Selection Feature

`CaptureSelectionPresenter` owns the AppKit overlay windows that provide region
and target selection across displays.
Coordinate conversion must be isolated and tested because AppKit screen points,
CoreGraphics global coordinates, and captured pixels can differ in origin and
scale.

`DisplayService` is the single source of truth for connected displays. It maps
each `CGDirectDisplayID` to its AppKit frame, Quartz frame, logical size, native
scale, and `NSScreen` without deriving one coordinate system from another.

The implemented selector creates one borderless overlay panel per display.
Region selection remains on the display where the drag begins and converts its
bottom-left AppKit rectangle into ScreenCaptureKit's display-local top-left
coordinates. The capture service aligns region edges to the target display's
physical pixel grid before capture so fractional points cannot trigger image
resampling. Window selection uses the front-to-back CoreGraphics window list
for hit testing and passes the selected window ID to ScreenCaptureKit. Full
screen capture from the menu displays a native overlay on every screen and uses
the display the user clicks; the global shortcut targets the display already
under the pointer. Escape is handled at the session level and produces no
capture or clipboard side effects.

### Capture Service

ScreenCaptureKit is the preferred capture API. The service translates a typed
request into framework configuration and returns a capture result. Framework
objects should not leak into unrelated views or persistence code.

### Permission Service

Checks screen-capture authorization, presents an explanation, requests access
where supported, and opens System Settings for recovery. Permission state is an
explicit workflow input, not an incidental capture error.

### Clipboard Service

Writes a compatible image representation to `NSPasteboard`. Clipboard work is
performed before optional save and preview behavior. The service returns a
typed error and does not present UI itself.

### File Service

Validates destinations and filename patterns, encodes the configured image
format, prevents collisions, writes atomically, and reports the resulting URL.
The implemented `CaptureFileService` supports Never, Always, and Ask Every Time;
PNG and JPEG encoding; JPEG quality; native `NSSavePanel`; security-scoped
folder bookmarks; exclusive non-overwriting writes; and collision-safe suffixes.

### Preview and Annotation Features

`CapturePreviewPresenter` owns two native preview panels. A lightweight,
non-activating thumbnail is
anchored to the bottom-right of the captured display, and its lifetime is driven
by `PreviewPolicy`. Clicking the thumbnail closes it and opens the full preview;
an explicitly opened full preview is not subject to the thumbnail's auto-hide
timer. Both panels retain the canonical `CGImage` in memory. The full preview
defaults to Fit and offers physical-pixel 1:1 rendering for inspection. Copy
always republishes the original capture, not the fitted preview representation.
Save As passes the same canonical image to the file service.
`AnnotationEditorPresenter` owns the separate native editor. The implemented
`AnnotationDocument`
stores pixel-coordinate elements over the immutable source `CGImage`, with
command history for Undo/Redo. `AnnotationRenderer` composites only when the
user exports, so Fit scaling never changes output resolution. Crop, Arrow,
Rectangle, editable Text, and Blur all use the same model. Copy and Save As
render a fresh full-resolution result without destructively mutating the source
bitmap after pointer events.

Hosted Preview panels are ordered out before their SwiftUI hosting controller
is detached and closed on a later main-actor turn. This prevents queued SwiftUI
constraint updates from targeting a window that AppKit is already closing.

### Settings and Shortcuts

Simple preferences use `UserDefaults` through a typed, versioned settings store.
The Settings scene uses native General, Capture, Shortcuts, and After Capture
tabs. Shortcut registration is isolated behind a service so conflicts and
library changes do not affect capture features.

### History

`CaptureHistoryStore` keeps the newest 10 captures within an approximate
256-MiB pixel-buffer budget. It is RAM-only, evicts oldest entries first, and
is released at app termination. Saved-file URLs are metadata; Never Save does
not create hidden persistent image history. `CaptureHistoryPresenter` owns the
native history panel and supplies Preview, Copy, Save As, Remove, and Clear
actions. SwiftData remains
reserved for a future durable/searchable-history requirement.

### Software Update Service

`SoftwareUpdateService` isolates Sparkle from the rest of the app and exposes
only readiness, the automatic-check preference, the installed version, and a
manual check action. Sparkle reads a signed public appcast and verifies each
archive with the EdDSA public key embedded in `Info.plist`. The sandboxed app
uses Sparkle's downloader and installer launcher services without granting the
main app general outbound network access. Automatic checks are disabled on
first launch, system profiling is disabled, and test processes do not start the
updater controller.

## 6. Capture Pipeline

```text
Trigger
  -> Ensure permission
  -> Optional delay
  -> Resolve target/selection
  -> Capture once
  -> Build canonical CaptureResult
  -> Copy to clipboard (if enabled)
  -> Execute save policy
  -> Execute preview policy
  -> Update allowed history metadata
```

Post-capture actions should be independently recoverable. For example, a folder
permission error may fail saving while clipboard copy and preview still succeed.

## 7. Concurrency

- Use Swift structured concurrency and Swift 6 strict concurrency.
- Keep UI state and AppKit window coordination on `@MainActor`.
- The current file service is main-actor isolated because it coordinates native
  panels and security-scoped access. Moving larger encoding and file writes to
  a safe background boundary remains a performance-hardening task.
- Make service protocols `Sendable` where their implementations safely support
  it.
- Define the policy for a second shortcut during an active capture. The MVP
  should reject or cancel-and-replace it consistently rather than overlap two
  selection sessions.

## 8. Error Model

Use domain-specific error types with actionable cases, such as permission
denied, target unavailable, capture failed, pasteboard write failed, invalid
destination, encoding failed, and disk write failed. Map technical errors to
short user messages at the presentation boundary while retaining underlying
errors for privacy-safe diagnostics.

Cancellation is a normal outcome and must not be reported as a failure.

## 9. Persistence and Privacy

- Store preferences in `UserDefaults`.
- Store user-approved captures only according to `SavePolicy`.
- Use exclusive file creation and collision-safe filenames so existing files
  are never overwritten.
- Keep image processing local for the MVP.
- Do not log image content, OCR text, window titles, or sensitive filenames by
  default.
- Document and test cleanup before introducing any temporary image cache.

## 10. Testing Strategy

- Unit-test policy evaluation, filename generation, coordinate conversion,
  settings migration, and state transitions.
- Use protocol-backed fakes for capture, clipboard, file, permission, and
  shortcut services.
- Integration-test pasteboard representations and file encoders.
- UI-test settings, menu commands, cancellation, and permission explanations
  where macOS automation allows stable coverage.
- Manually verify Retina, mixed-scale multi-monitor, Spaces, full-screen apps,
  and common paste destinations before release.

## 11. Key Technical Risks

- Correct coordinate conversion across mixed-scale displays
- Screen Recording permission lifecycle and relaunch behavior
- Window selection and shadow/border consistency
- App Sandbox access to custom persistent folders
- Reliable global shortcut registration and conflict reporting
- Preview focus behavior that does not interrupt the destination application

Resolve these risks with small vertical prototypes before investing in the full
annotation editor.
