# Changelog

## Unreleased

_No unreleased changes._

## 1.3.0 — 2026-07-17

### Added

- On-device text recognition with Apple Vision. **Copy Text** is available in
  the full Preview window (⌘T), on every Capture History row, and in the
  Annotation editor. In the editor, a crop restricts recognition to the
  cropped region and a blur keeps the text it covers out of the result.
- **Capture Text** global shortcut (default ⌃⇧T): select a region and the
  recognized text lands on the clipboard — with no image on the clipboard, no
  saved file, no preview, and no history entry. Recognition runs entirely on
  this Mac and languages are detected automatically.
- Sidebar-style Settings window with an app-identity header, section list,
  and version footer, replacing the previous tab layout.

### Changed

- Debug builds now use the separate bundle identifier
  `com.jesdx.capdeck.debug`, so development builds no longer share the Screen
  Recording permission or preferences with the installed release app.

## 1.2.3 — 2026-07-15

### Fixed

- A capture shortcut no longer cancels an in-progress Save dialog. When the
  Preview, Annotation editor, or History window has a save sheet open, a new
  capture request is ignored instead of silently tearing the sheet down.

### Changed

- Moved native windowing code into per-feature presenters so Services stay
  focused on system access. No user-visible behavior change.

## 1.2.2 — 2026-07-14

### Changed

- Full Preview now closes after a successful Copy or Save, keeping the
  capture-to-destination workflow fluid.
- Cancelling Save or encountering a Copy/Save failure keeps Preview open so the
  user can retry without losing context.

## 1.2.1 — 2026-07-14

### Changed

- Moved the manual update action exclusively into **Settings > General >
  Software Updates** so it cannot be mistaken for a capture command in the
  menu bar.

## 1.2.0 — 2026-07-14

### Added

- Added a native Software Updates section in Settings with manual checks and an
  opt-in automatic-check preference.
- Added a **Check for Updates…** command to the menu bar.
- Integrated Sparkle 2 with signed appcast and archive verification, sandboxed
  downloader and installer services, and no system-profile transmission.
- Added a repeatable signed-update feed preparation script and automated tests
  for update readiness and preference transitions.

### Fixed

- Release archives now derive their version from the built app instead of a
  hardcoded filename.
- Release checksums now contain a portable relative archive filename, so
  recipients can verify them from any directory.
- The release build now fails early when required Sparkle security keys are
  absent.
- Local ad-hoc release builds now re-sign Sparkle's nested helpers in the
  required order and apply the development-only library-validation exception,
  preventing a launch-time framework rejection.
- Kept an explicit placeholder under the Unreleased changelog section so
  changelog readers do not render an accidental blank section.

## 1.1.1 — 2026-07-14

### Fixed

- Save As now opens as a native sheet above the Preview, History, or Annotation
  window that invoked it. Ask Every Time remains app-modal and is explicitly
  raised above CapDeck's floating utility windows.
- Screen Recording permission now invokes the macOS request only once and no
  longer stacks CapDeck's recovery alert over the system permission prompt.

## 1.1.0 — 2026-07-14

### CapDeck Rebrand

- Renamed the app, Xcode project, schemes, targets, tests, package, and
  repository to CapDeck.
- Changed the bundle identifier to `com.jesdx.capdeck`, intentionally creating
  a clean macOS app identity and permission state.
- Updated the app mark from L to C, regenerated the brand lockup, and renamed
  brand assets.
- Updated release scripts, environment variables, documentation, and filename
  defaults for the CapDeck identity.

## 1.0.0 — 2026-07-14

First complete personal capture-workflow release.

### Capture

- Region, visual/direct window, and selected-display capture.
- Mixed Retina and standard-density multi-display support.
- Physical-pixel-aligned output without preview-driven resampling.
- Configurable delay, Escape cancellation, permission recovery, and target
  disappearance handling.

### Workflow

- Lossless PNG/TIFF clipboard output.
- Never Save, Always Save, and Ask Every Time policies.
- PNG/JPEG, filename tokens, collision-safe writes, and sandboxed custom-folder
  access.
- Native bottom-right thumbnail plus Fit and physical-pixel 1:1 preview.
- Configurable global shortcuts and Launch at Login.

### Annotation and History

- Non-destructive Crop, Arrow, Rectangle, editable Text, and Blur.
- Undo/Redo, element selection/deletion, Copy Annotated, and Save Annotated.
- Privacy-safe in-memory Capture History with Copy, Preview, Save As, Remove,
  Clear, count limit, and memory budget.

### Quality

- Native accessibility labels and keyboard paths for core workflows.
- Main-thread-free image encoding and file writes.
- Automated unit, integration, performance, and critical UI coverage.
