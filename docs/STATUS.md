# CapDeck Implementation Status

Last updated: 2026-07-14

This document is the current implementation snapshot. `TASKS.md` remains the
source of truth for checklist counts, while product behavior and technical
boundaries live in `PRODUCT_REQUIREMENTS.md` and `ARCHITECTURE.md`.

## Progress

| Scope | Complete | Progress | Meaning |
| --- | ---: | ---: | --- |
| V1 engineering implementation | 49 / 49 | 100% | All in-repository V1 implementation and automated verification |
| MVP owner-review gate | 49 / 52 | 94% | Engineering-complete V1 plus three owner-run compatibility checks |
| V1.2 maintenance additions | 1 / 1 | 100% | Signed software update workflow and release hygiene |
| Full tracked roadmap | 56 / 70 | 80% | MVP, V2, V3, and open product decisions |

Percentages are checklist-based and rounded to the nearest whole percent. They
measure completed deliverables, not elapsed development time.

## Working Now

- Native menu bar application with an icon-only menu bar item.
- Region, window, and selected-display capture.
- Multi-display targeting across mixed Retina and standard-density displays.
- Physical-pixel-aligned capture without preview-driven resampling.
- Automatic clipboard copy using lossless PNG and TIFF pasteboard
  representations.
- Configurable native global shortcuts with conflict reporting.
- Configurable capture delay and Escape cancellation.
- Native Settings tabs for General, Capture, Shortcuts, and After Capture.
- A one-click AI Workflow preset: Auto Copy, Never Save, and a two-second
  preview.
- Launch at Login through `SMAppService.mainApp`, including approval-state and
  signed-build feedback.
- Restore All Defaults plus versioned settings migration.
- A native, non-activating post-capture thumbnail at the bottom-right of the
  source display. Clicking it opens the full preview in Fit mode, with
  physical-pixel 1:1 available for inspection plus Copy, Save As, and Close
  actions.
- Never Save, Always Save, and Ask Every Time policies.
- Sandboxed custom-folder access using a persisted security-scoped bookmark.
- PNG and JPEG output, JPEG quality control, filename tokens, exclusive writes,
  and collision-safe names.
- Independent post-capture outcomes: a save failure does not remove a
  successful clipboard result or suppress preview.
- A native annotation editor opened from Preview with non-destructive Crop,
  Arrow, Rectangle, editable Text, and Blur tools; element selection/deletion;
  Undo/Redo; and full-resolution Copy Annotated and Save Annotated export.
- Privacy-safe Capture History retained only in RAM for the current session,
  bounded to 10 captures and approximately 256 MiB, with Preview, Copy, Save
  As, Remove, and Clear actions.
- A safe menu-bar visibility setting: hiding the status icon keeps CapDeck in
  the Dock so Settings can restore it.
- A signed Sparkle update path with manual checks in Settings,
  plus opt-in automatic checks that send no system profile.

## Latest Delivered Changes

1. Corrected full-screen and region capture sizing for every connected display.
2. Aligned fractional region bounds to the target display's physical pixel
   grid to remove blur.
3. Added a native 1:1 preview so source pixels can be inspected directly.
4. Added the complete file-saving pipeline and Settings controls.
5. Added structured native Settings, the AI Workflow preset, Launch at Login,
   Restore Defaults, and settings migration.
6. Added automated coverage for save-policy isolation, filename validation,
   PNG/JPEG dimensions, collision-safe naming, settings persistence, migration,
   presets, and login-item state.
7. Changed post-capture preview to a macOS-style bottom-right thumbnail that
   opens the existing full-resolution preview only when clicked.
8. Added permission-revocation recovery during an active capture and isolated
   disappearing-display failures before clipboard, save, or preview work.
9. Added regression coverage for clipboard failure isolation and adjacent-pixel
   integrity in the lossless PNG pasteboard representation.
10. Prevented an AppKit/SwiftUI constraint race when closing a full Preview and
    immediately starting another capture.
11. Added the first annotation vertical slice: Rectangle, command-based
    Undo/Redo, and clipboard export without mutating the source capture.
12. Made a new capture dismiss active Preview and Annotation windows before
    selection so CapDeck UI cannot appear in the result.
13. Completed the annotation toolset with Crop, Arrow, editable Text, and Blur,
    plus element selection/deletion and annotated Save As.
14. Added renderer regression coverage for crop orientation, blur locality,
    text editing, deletion, and mixed Arrow/Text export.
15. Added bounded in-memory Capture History and explicit cleanup controls.
16. Completed keyboard navigation, accessibility labels, critical UI tests,
    launch/4K encoding performance checks, and release packaging.
17. Attached Save As to its invoking Preview, History, or Annotation window so
    the native chooser cannot appear behind CapDeck UI.
18. Prevented repeated Screen Recording prompts and removed the overlapping
    app recovery alert from the initial macOS permission request.
19. Added signed software update checks with native Settings and menu commands,
    sandboxed download/install helpers, and updater unit/UI coverage.
20. Made release archive versions derive from the built app and made checksum
    files portable across machines.
21. Corrected manual Sparkle signing for local ad-hoc releases so the installed
    app and its nested helpers pass both static and runtime launch validation.
22. Made successful Preview Copy and Save actions close the workflow while
    preserving Preview after cancellation or failure for immediate retry.

## Verification Snapshot

- 69 unit and integration tests pass; 5 critical/launch UI tests pass.
- Release configuration builds successfully for macOS 14 or later.
- The installed Release app launches from `/Applications/CapDeck.app`.
- Real Release smoke testing confirms global shortcut capture updates the
  pasteboard.
- Real Release window-capture testing confirms the thumbnail appears on the
  source display, Fit is selected by default, and Preview source dimensions
  exactly match the PNG dimensions on the pasteboard.
- A live three-display matrix passes Full Screen, Region, and Window capture on
  1x landscape, 2x Retina, and 1x portrait displays. Exact results are recorded
  in [ACCEPTANCE.md](ACCEPTANCE.md).
- Five consecutive Preview close/open stress iterations pass after fixing the
  hosted-panel constraint-update race, with no new crash report.
- Real Release annotation testing confirms every tool accepts pointer input,
  Crop reports its exact output size, annotated clipboard content differs from
  the original while retaining the expected dimensions, Save As opens safely,
  and the Editor remains stable through cancellation and closing.
- Ask Every Time presents the native `Save CapDeck Capture` panel.
- The app remains sandboxed with user-selected read/write file access.
- Release launch averages 0.402 seconds in the UI metric, 4K PNG encoding takes
  approximately 0.23 seconds on the test Mac, and idle RSS is approximately
  77–79 MiB.

## Capture and Preview Acceptance Gate

The v1 baseline is code-complete and verified on the connected three-display
setup for capture modes, native pixel sizing, source-display thumbnail
placement, Fit/1:1 preview behavior, lossless clipboard output, save/preview
isolation, permission denial and revocation, and target-display disappearance.

Three external/manual matrix items are handed off to the owner and remain
outside the completed V1 engineering gate:

1. Paste into ChatGPT, Codex, Claude, Messenger, Slack, and Discord and record
   whether each destination keeps the original attachment dimensions.
2. Physically attach and detach a display during selection and immediately
   before capture on mixed Retina and standard-density setups.
3. Repeat the compatibility matrix on additional supported macOS 14+ hardware.

## V1.2.2 Release State

The personal V1 implementation, automated quality gate, documentation, signed
update metadata, local release archive, Save As window-ordering fix, stable
permission-request flow, and ad-hoc signing are complete. The update channel
cryptographically verifies its feed and archives. Public Gatekeeper-friendly
distribution still requires an Apple Developer ID Application certificate plus
notarization; no such identity is installed on this Mac. The remaining
checklist items are owner-review evidence, not missing capture functionality.

## Recommended Next Milestone

Use V1.2.2 as the maintained CapDeck V1 baseline. The owner can complete the review
matrix independently before selecting the first V2 feature; OCR remains the
smallest useful next vertical slice.
