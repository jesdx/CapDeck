# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## What this is

CapDeck is a native macOS screenshot app (Swift 6 / SwiftUI / AppKit) optimized for one path: **Capture → Clipboard → Paste → Done**. It is a menu-bar (`.accessory`) app, App Sandboxed, local-first, no account, targeting **macOS 14+** (required by `SCScreenshotManager`). Bundle id: `com.jesdx.capdeck` (Debug builds use `com.jesdx.capdeck.debug` so dev builds do not share Screen Recording/TCC permission or UserDefaults with the installed release build).

## Build, test, run

There is no `Package.swift`; this is an Xcode project. Prefer `xcodebuild` from the CLI.

```sh
# Build (Debug)
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck -destination 'platform=macOS' build

# Run all unit tests
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck \
  -destination 'platform=macOS' -only-testing:CapDeckTests test

# Run a single test (target/suite/method — suites live in CapDeckTests/<Feature>Tests.swift)
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck -destination 'platform=macOS' \
  -only-testing:CapDeckTests/SelectionGeometryTests/normalizesDragInAnyDirection test

# Local release archive (ad-hoc signed unless CAPDECK_SIGNING_IDENTITY is set)
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer Scripts/build-release.sh
```

Run to launch: open the project in Xcode, select the `CapDeck` scheme + a local Mac destination, Run, then use the menu-bar mark. Default global shortcuts (active while any app is focused): `Ctrl+Shift+J` region, `Ctrl+Shift+K` window, `Ctrl+Shift+L` full screen, `Ctrl+Shift+T` capture text (region → OCR → clipboard, no image/preview/history), `Ctrl+Shift+9` history. First capture triggers the macOS Screen Recording permission prompt.

Lint/format: SwiftFormat (`.swiftformat`, 4-space indent, `before-first` arg wrapping, trailing commas) and SwiftLint (`.swiftlint.yml`). `force_unwrapping` is an opt-in rule and force unwraps/`try!` are disallowed in production code — the release-build config also enforces `NeverForceUnwrap`/`NeverUseForceTry`.

## Architecture

The layering is strict and worth preserving — **Views render state and emit intent; Coordinators own workflow ordering and product policy; Services wrap exactly one system capability and never present UI.** Models never depend on views. Dependencies are injected through initializers; there are no business-logic singletons.

### Wiring
`CapDeckApp` (`@main`) hosts a `MenuBarExtra` + `Settings` scene and owns a single `DependencyContainer` (`CapDeck/App/DependencyContainer.swift`). The container is the composition root: it constructs every concrete service, injects protocol-typed dependencies, builds the `CaptureCoordinator`, and registers global shortcuts. To swap a real service for a fake (tests), pass it to `DependencyContainer.init` — the initializer takes optional protocol-typed overrides and falls back to real implementations.

`AppDelegate` manages activation policy: `.accessory` when the menu-bar icon is visible, `.regular` otherwise (and `.regular` under `CAPDECK_UI_TESTING=1`).

### Capture pipeline
`CaptureCoordinator` (`Features/Capture/`) is a `@MainActor` state machine (`CaptureWorkflowState`: idle → requestingPermission → delaying → selecting → capturing → completed/cancelled/permissionDenied/failed). It sequences: ensure permission → optional delay → resolve selection/target → capture once → build the **canonical `CaptureResult`** → copy to clipboard → run save policy → run preview policy → record allowed history. `state.isBusy` gates re-entry so a second shortcut during an active capture is ignored rather than overlapping sessions.

Post-capture actions are **independently recoverable**: a folder-permission save failure must not stop clipboard copy or preview.

The canonical `CGImage`/`CaptureResult` stays in memory through the whole pipeline. Clipboard, file, preview, and annotation all derive representations from it — never recapture, and never mutate the source bitmap destructively. Fit-scaling in preview must not change exported/clipboard resolution.

### Services (`CapDeck/Services/*`)
Each is a protocol + concrete impl injected by the container:
- `ScreenCaptureService` (ScreenCaptureKit; framework types stay behind this boundary)
- `DisplayService` — **single source of truth for displays.** Maps each `CGDirectDisplayID` to AppKit frame, Quartz frame, logical size, native scale, and `NSScreen`. Do not derive one coordinate system from another elsewhere.
- `ScreenCapturePermissionService`, `PasteboardClipboardService`, `CaptureFileService` (Never/Always/Ask save policies, PNG/JPEG, `NSSavePanel`, security-scoped folder bookmarks, exclusive non-overwriting writes with `-2`/`-3` collision suffixes), `GlobalShortcutService`, `LaunchAtLoginService` (`SMAppService.mainApp`), `SoftwareUpdateService` (Sparkle; signed feed + EdDSA-verified updates stay behind this boundary).

### Presenters (`CapDeck/Features/*/Presentation/`)
The AppKit UI that presents windows lives here, not in Services (services never present UI). Each owns its `NSPanel`/sheet lifetime: `CapturePreviewPresenter`, `AnnotationEditorPresenter`, `CaptureHistoryPresenter`, and `CaptureSelectionPresenter` (protocols `CapturePreviewPresenting`/`AnnotationEditing`/`CaptureHistoryPresenting`/`CaptureSelectionPresenting`, injected by the container). A capture is ignored while any of them reports `isPresentingModalSheet` so an in-progress save dialog is never torn down. The menu-bar content view is `Features/MenuBar/MenuBarContentView.swift`.

### Coordinate conversion (highest-risk area)
AppKit screen points, CoreGraphics global coordinates, and captured pixels differ in origin (bottom-left vs top-left) and scale. Region selection converts a bottom-left AppKit rect on the drag's origin display into ScreenCaptureKit display-local top-left coordinates, then aligns edges to the physical pixel grid before capture (fractional points would trigger resampling). This logic lives in `Features/Selection/SelectionGeometry.swift` and **must have unit tests** for any change.

### Preview & Annotation
Preview uses two AppKit panels: a non-activating bottom-right thumbnail (lifetime driven by `PreviewPolicy`) and a full preview. Panels must not steal focus from the user's paste destination unless the Editor is explicitly opened. Panels are ordered out before their SwiftUI hosting controller detaches (on a later main-actor turn) to avoid constraint updates targeting a closing window. `AnnotationDocument` stores pixel-coordinate elements over the immutable source `CGImage` with undo/redo command history; `AnnotationRenderer` composites only at export.

### History
`CaptureHistoryStore` (`Features/History/`) is **RAM-only**: newest 10 captures within ~256 MiB pixel budget, oldest-evicted-first, fully released at termination. It writes no hidden image files — "Never Save" must never create persistent image history. SwiftData is intentionally not used (reserved for a future durable-history requirement).

## Conventions

- Swift 6 strict concurrency. UI state and AppKit window coordination on `@MainActor`. No image encoding or file I/O synchronously on the main actor. Check cancellation around delay/selection/capture/processing.
- Cancellation (e.g. Escape) is a **normal outcome**, never reported as an error. Use typed, localized domain errors and map to short user messages only at the presentation boundary.
- One primary type per file, named after the type; extensions as `Type+Capability.swift`. No `Helpers.swift`/`Utilities.swift` dumping grounds. Feature code lives with its feature.
- Privacy: do not log image content, OCR text, window titles, or sensitive filenames.
- Add a regression test with every testable bug fix. Name tests by behavior (e.g. `askEveryTimeKeepsClipboardResultWhenSaveIsDeclined`).

## Reference docs

Project docs live under `docs/`: `docs/ARCHITECTURE.md` (authoritative design + risks), `docs/CODING_GUIDELINES.md`, `docs/PRODUCT_REQUIREMENTS.md` (record user-visible behavior here), `docs/TASKS.md` (update on scope/status change), `docs/STATUS.md`, `docs/ACCEPTANCE.md`.
