# Capture and Preview Acceptance

Last executed: 2026-07-14

This matrix records live Release-build verification in addition to automated
tests. Pixel dimensions are read from both the full Preview source label and
the lossless PNG representation on `NSPasteboard`.

## Test Environment

| Display | Layout | Scale | Native pixels |
| --- | --- | ---: | ---: |
| DELL U2419H (1) | Landscape primary | 1x | 1920 × 1080 |
| Built-in Retina Display | Landscape secondary | 2x | 3024 × 1964 |
| DELL U2419H (2) | Portrait secondary | 1x | 1080 × 1920 |

The CapDeck 1.2.2 release is verified under bundle identifier
`com.jesdx.capdeck`. The initial native Screen Recording request appears once;
later denied attempts use CapDeck's recovery path without stacking another
system prompt.

## Live Release Results

| Mode | Display | Selected/source size | Clipboard PNG | Result |
| --- | --- | ---: | ---: | --- |
| Full Screen | Primary DELL | 1920 × 1080 | 1920 × 1080 | Pass |
| Full Screen | Built-in Retina | 3024 × 1964 | 3024 × 1964 | Pass |
| Full Screen | Portrait DELL | 1080 × 1920 | 1080 × 1920 | Pass |
| Region | Primary DELL | 320 × 240 points | 320 × 240 | Pass |
| Region | Built-in Retina | 320 × 240 points | 640 × 480 | Pass |
| Region | Portrait DELL | 320 × 240 points | 320 × 240 | Pass |
| Window | Chrome on primary DELL | 1920 × 1050 | 1920 × 1050 | Pass |
| Window | ChatGPT on built-in Retina | 3024 × 1898 | 3024 × 1898 | Pass |
| Window | Safari on portrait DELL | 1080 × 1050 | 1080 × 1050 | Pass |

For every inspected capture, the thumbnail appeared on the source display,
clicking it opened the full Preview, and Fit was selected by default. The 1:1
mode remained available without changing the canonical capture.

Successful Copy and Save actions close full Preview. A cancelled Save or failed
Copy/Save leaves it open so the operation can be retried.

## Stability Regression

Closing the full Preview and immediately starting a new capture originally
exposed an AppKit/SwiftUI constraint-update race. The Preview service now orders
the hosted panel out before detaching its hosting controller on a later
main-actor turn. The exact close-and-capture sequence passed once, followed by
five consecutive close/open stress iterations with no new crash report.

## Automated Coverage

The 69 passing unit and integration tests cover selection geometry, physical
pixel sizing, thumbnail layout, lossless PNG edge integrity, save and preview
failure isolation, permission denial and revocation, and target-display
disappearance. Annotation coverage adds bounds clipping, Retina canvas mapping,
command history, immutable-source rendering, Arrow/Text composition, editable
Text lifecycle, region-limited Blur, top-left Crop coordinates, and exact output
dimensions.

Save-panel coverage creates a real floating parent panel and confirms that
Save As attaches an `NSSavePanel` sheet to that parent before cancellation,
preventing the chooser from appearing behind Preview, History, or Annotation.

Five UI tests cover the Settings safety controls, software-update controls,
critical menu commands, Light/Dark launch, and launch performance. On the release test Mac, launch
averages 0.402 seconds, 4K PNG encoding is approximately 0.23 seconds, and idle
RSS is approximately 77–79 MiB.

## History Release Smoke Test

- A successful Release capture increments the menu History count.
- History appears on the display under the pointer and reports capture pixel
  dimensions, session memory use, and saved-file metadata when present.
- Preview opens the full Preview directly; Copy, Save As, Remove, and Clear are
  available without creating hidden persistent files.
- Starting a new capture dismisses History before selection, preventing CapDeck
  UI from appearing in the result.
- In the final installed V1.2.2 build, History Preview opens `CapDeck Preview`
  directly rather than creating another transient thumbnail.

## Software Update Release Gate

- Settings exposes the installed version, manual **Check for Updates** action,
  and an automatic-check preference that is off by default.
- The menu bar intentionally contains no update command; the manual action is
  isolated in Settings so it cannot be confused with capture commands.
- The release app embeds the expected feed URL and EdDSA public key, enables
  signed-feed and pre-extraction verification, and sends no system profile.
- The release archive checksum verifies after the archive and checksum are
  copied to an unrelated directory.
- The signed appcast references the matching release version and archive.

## Menu Bar Recovery Smoke Test

- With the menu-bar icon enabled, CapDeck exposes exactly one native status
  item.
- With it disabled, the status item disappears while the process remains
  running with regular-app activation, leaving Dock/Settings as the recovery
  path.
- Restoring the preference and relaunching returns the status item; the final
  installed state leaves the icon enabled.

## Annotation Release Smoke Test

- Preview opens the native `CapDeck Annotate` editor.
- Rectangle, Arrow, Text, Blur, and Crop each accept pointer input in the native
  Release editor, and Crop updates the displayed output pixel dimensions.
- Text can be selected, edited, or deleted; all document commands participate
  in Undo and Redo.
- Copy Annotated retains the uncropped source dimensions, or emits the exact
  selected crop dimensions, while producing content distinct from the original
  clipboard PNG.
- Save Annotated opens the native `Save CapDeck Capture` panel and cancellation
  safely returns to the editor.
- Closing the Editor and immediately capturing again does not crash.
- Starting a new capture while the Editor is open dismisses it before capture.

## Owner Review Handoff

- Paste into ChatGPT, Codex, Claude, Messenger, Slack, and Discord and record
  the attachment dimensions reported or retained by each destination.
- Physically attach and detach an external display during selection and just
  before capture. Software cannot reproduce the same WindowServer transition
  with sufficient confidence.
