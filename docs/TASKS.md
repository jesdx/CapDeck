# CapDeck Tasks and Roadmap

This is the working delivery checklist. Product behavior belongs in
`PRODUCT_REQUIREMENTS.md`; this file tracks implementation status.

## Progress Snapshot — 2026-07-14

- V1 engineering implementation: **49/49 — 100%**
- MVP review gate including owner-run checks: **49/52 — 94%**
- V1.2 maintenance additions: **1/1 — 100%**
- Full tracked roadmap including V2, V3, and decisions: **56/70 — 80%**
- Automated tests passing: **69 unit/integration + 5 UI**

See [STATUS.md](STATUS.md) for implemented behavior, verification, recent
changes, remaining work, and the recommended next milestone.

## Phase 0 — Foundation

- [x] Create the Xcode project and test targets.
- [x] Add project overview, requirements, architecture, coding guidelines, and
  roadmap documents.
- [x] Confirm the minimum supported macOS version against required
  ScreenCaptureKit APIs.
- [x] Add `.gitignore` for Xcode and macOS generated files.
- [x] Add SwiftFormat and SwiftLint configuration.
- [x] Establish the feature-oriented source layout as implementation begins.
- [x] Add an app settings model with documented defaults.
- [x] Add a dependency container for system services.

## Phase 1 — Clipboard-First Capture Slice

- [x] Implement screen-capture permission status and recovery UI.
- [x] Implement a typed `CaptureRequest` and `CaptureResult`.
- [x] Implement full-screen capture for a selected display.
- [x] Implement pasteboard image writing.
- [x] Add the first global capture shortcut.
- [x] Wire shortcut -> capture -> clipboard end to end.
- [ ] Verify paste behavior in ChatGPT, Codex, Claude, Messenger, Slack, and
  Discord.
- [x] Add unit tests for the first vertical slice.
- [x] Add an integration test for the real pasteboard representation.

## Phase 2 — Capture Modes

- [x] Build the multi-display region-selection overlay.
- [x] Implement point-to-pixel coordinate conversion and tests.
- [x] Implement region capture and Escape cancellation.
- [x] Build window selection with hover highlighting.
- [x] Implement window capture.
- [x] Add configurable delay.
- [x] Validate mixed Retina/non-Retina monitor configurations.

## Phase 3 — Save and Preview Policies

- [x] Implement Never Save, Always Save, and Ask Every Time.
- [x] Add custom folder selection and persisted access where required.
- [x] Add PNG and JPEG encoding.
- [x] Implement filename pattern validation and collision-safe generation.
- [x] Implement Always, Never, and Auto Hide preview policies.
- [x] Add the two-second AI Workflow Mode preset.
- [x] Ensure clipboard success is independent of save and preview failures.

## Phase 4 — Menu Bar, Settings, and Shortcuts

- [x] Build the menu bar menu and commands.
- [x] Build General, Capture, Shortcuts, and After Capture settings sections.
- [x] Implement configurable region, window, and full-screen shortcuts.
- [x] Report shortcut registration conflicts.
- [x] Implement Launch at Login.
- [x] Define safe behavior when the menu bar icon is hidden.
- [x] Add settings persistence and migration tests.
- [x] Add signed manual and opt-in automatic software update checks.

## Phase 5 — Annotation and History

- [x] Create the annotation document model.
- [x] Add crop, arrow, rectangle, text, and blur tools.
- [x] Add undo and redo.
- [x] Export annotated results to clipboard and/or file.
- [x] Add privacy-safe bounded history.
- [x] Add clear-history and temporary-data cleanup behavior.

## Phase 6 — MVP Hardening

- [x] Add accessibility labels and complete keyboard navigation.
- [x] Test permission denial, revocation, and recovery.
- [ ] Test display attach/detach and target disappearance.
- [x] Test file permission, disk-full, and invalid-pattern failures.
- [x] Profile startup, capture latency, memory, and image encoding.
- [x] Run unit, integration, and critical UI test suites.
- [ ] Perform a manual compatibility matrix across target macOS versions and
  common paste destinations.
- [x] Prepare app icon, privacy copy, release configuration, and local signing.

## Owner Review Handoff

V1 engineering is complete. The three unchecked Phase 1/6 items above are
retained as owner-run review evidence and do not block the frozen V1 code
baseline. They must not be marked complete until the corresponding external
apps, physical display transitions, and additional supported Mac environments
have actually been reviewed.

## V2

- [~] OCR with Vision
  - [x] Slice 1: `TextRecognizing` service (Vision) + `CaptureTextCopier`
    workflow + "Copy Text" action in the full Preview window.
  - [x] Slice 2: "Copy Text" in History and the Annotation editor; the editor
    recognizes the rendered/cropped image, so a crop restricts OCR to that
    region and blur keeps redacted text out.
  - [ ] Slice 3: dedicated "Capture Text" shortcut — region → OCR →
    clipboard with no preview.
- [ ] QR code detection
- [ ] Floating image window
- [ ] Pin image behavior
- [ ] Expanded annotation tools

## V3

- [ ] Scrolling screenshot
- [ ] Screen recording
- [ ] GIF recording
- [ ] Cloud sync
- [ ] Share links
- [ ] AI-assisted annotation

## Open Decisions

- [x] Choose and document macOS 14 as the minimum deployment target.
- [x] Keep App Sandbox enabled for the shipping app.
- [x] Include native window shadows and exclude the selection border.
- [x] Define temporary history retention and cleanup limits.
- [x] Reject a second capture trigger while a capture workflow is active.
- [x] Use Control-Shift-J/K/L as defaults to avoid macOS screenshot shortcuts.
