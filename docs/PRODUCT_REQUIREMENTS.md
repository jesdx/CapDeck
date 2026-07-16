# CapDeck Product Requirements

## 1. Purpose

This document defines the functional and quality requirements for the CapDeck
MVP. Requirement identifiers are stable references for implementation, tests,
and task tracking.

## Implementation Status — 2026-07-14

| Requirement area | Status |
| --- | --- |
| Capture (CAP) | Implemented; broader permission and display-change hardening remains |
| Clipboard (CLP) | Implemented; manual paste-destination matrix remains |
| Save Policy (SAV) | Implemented, including sandboxed custom-folder access |
| Preview (PRV) | Implemented, including the annotation action |
| Annotation (ANN) | Implemented: Crop, Arrow, Rectangle, editable Text, Blur, Undo/Redo, Copy, and Save As |
| Menu Bar and Shortcuts (UI) | Core menu and configurable shortcuts implemented; keyboard/accessibility audit remains |
| Settings (SET) | Native sections, persistence, migration, presets, and Launch at Login implemented; menu icon visibility remains |
| History (HIS) | Implemented and verified |
| Software Updates (UPD) | Implemented with signed manual and opt-in automatic checks |

Checklist percentages and verification details are maintained in
[STATUS.md](STATUS.md).

## 2. User Workflow

The default workflow is:

```text
Shortcut -> Capture -> Clipboard -> Optional save -> Optional preview -> Done
```

The image must be available to paste as soon as capture processing completes.
Saving and previewing must not make the clipboard workflow unnecessarily wait.

## 3. Functional Requirements

### 3.1 Capture

- **CAP-001 Region capture:** The user can drag to select a rectangular region.
- **CAP-002 Window capture:** The user can select a visible window to capture.
- **CAP-003 Full-screen capture:** The user can capture a chosen display.
- **CAP-004 Multiple displays:** Selection and capture use the correct display
  coordinate space in multi-monitor configurations.
- **CAP-005 Retina fidelity:** Output preserves the correct backing scale and is
  not unintentionally downsampled.
- **CAP-006 Delay:** The user can configure a capture delay, including no delay.
- **CAP-007 Cancellation:** Escape cancels selection without changing the
  clipboard, creating a file, or showing a result preview.
- **CAP-008 Permission handling:** The app explains Screen Recording permission,
  can open the relevant System Settings page, and recovers after permission is
  granted.

### 3.2 Clipboard

- **CLP-001 Automatic copy:** When Auto Copy is enabled, every successful capture
  is written to the macOS pasteboard.
- **CLP-002 Paste compatibility:** Clipboard output can be pasted into common AI,
  chat, and document applications as an image.
- **CLP-003 Failure isolation:** A save or preview failure does not remove a
  successfully copied clipboard image.

### 3.3 Save Policy

- **SAV-001 Never Save:** The app creates no persistent image file.
- **SAV-002 Always Save:** The app saves every successful capture to the
  configured folder.
- **SAV-003 Ask Every Time:** After capture, the app presents a non-destructive
  choice to save or discard the file while keeping the image on the clipboard.
- **SAV-004 Destination:** The user can choose a custom save folder.
- **SAV-005 Format:** The user can select a supported image format. MVP formats
  are PNG and JPEG.
- **SAV-006 Filename pattern:** The user can configure a validated filename
  pattern using documented date/time tokens.
- **SAV-007 Collision safety:** Existing files are never silently overwritten.
- **SAV-008 Errors:** Save failures show a useful error without losing the
  clipboard result.

### 3.4 Preview

- **PRV-001 Always:** A non-activating thumbnail appears at the bottom-right of
  the captured display after every successful capture. Clicking it opens the
  full preview.
- **PRV-002 Never:** No preview appears after capture.
- **PRV-003 Auto Hide:** The post-capture thumbnail appears and closes after a
  configurable short duration; AI Workflow Mode defaults to two seconds. A
  full preview opened explicitly by the user does not auto-close.
- **PRV-004 Dismiss:** The user can dismiss an active preview immediately with
  the keyboard or pointer.
- **PRV-005 Actions:** The preview exposes relevant save, annotate, copy, and
  close actions without blocking an already completed clipboard copy.

### 3.5 Annotation

- **ANN-001 Crop:** The user can crop the captured image.
- **ANN-002 Shapes:** The user can add arrows and rectangles.
- **ANN-003 Text:** The user can add and edit text labels.
- **ANN-004 Blur:** The user can obscure a selected image region.
- **ANN-005 History:** Annotation actions support undo and redo.
- **ANN-006 Export:** Applying annotations updates the result selected by the
  user for clipboard and/or saving without modifying unrelated source files.

### 3.6 Menu Bar and Shortcuts

- **UI-001 Menu bar:** The menu provides Capture Region, Capture Window, Full
  Screen, Settings, History, and Quit commands.
- **UI-002 Global shortcuts:** Region, window, and full-screen capture each have
  configurable global shortcuts.
- **UI-003 Conflict feedback:** The app reports shortcut registration conflicts
  and does not claim a shortcut that could not be registered.
- **UI-004 Keyboard operation:** Capture selection, cancellation, preview, and
  common actions are usable without a pointer where practical.

### 3.7 Settings

- **SET-001 General:** The user can enable Launch at Login and control menu bar
  icon visibility.
- **SET-002 Capture:** The user can configure folder, format, filename pattern,
  and delay.
- **SET-003 After Capture:** The user can configure Auto Copy, save policy, and
  preview policy.
- **SET-004 Persistence:** Settings survive app restarts.
- **SET-005 Safe defaults:** First launch enables Auto Copy, uses Never Save, and
  uses Auto Hide preview so the app is immediately useful without leaving
  unwanted files.

### 3.8 History

- **HIS-001 Session history:** The MVP may show captures that still have locally
  available image data or saved-file references.
- **HIS-002 Privacy:** History remains local and can be cleared by the user.
- **HIS-003 Never Save semantics:** History must not quietly turn a Never Save
  capture into a permanent user file. Any temporary cache must have a documented
  retention policy and be automatically cleaned.

### 3.9 Software Updates

- **UPD-001 Manual check:** General Settings provides an explicit check for
  updates; the capture-oriented menu bar does not expose this action.
- **UPD-002 Automatic checks:** Periodic checks are opt-in and can be disabled
  at any time.
- **UPD-003 Authenticity:** Update metadata and archives are cryptographically
  verified before installation.
- **UPD-004 Privacy:** Update checks send no capture content, analytics, or
  system profile.
- **UPD-005 User control:** CapDeck asks before installing an available update.

## 4. Non-Functional Requirements

- **NFR-001 Native:** The application uses native macOS technologies and follows
  platform interaction conventions.
- **NFR-002 Startup:** Menu bar readiness and shortcut registration should feel
  immediate after launch.
- **NFR-003 Performance:** Capture processing must avoid unnecessary encoding,
  disk writes, and main-thread image work.
- **NFR-004 Reliability:** A failure in one post-capture action must not corrupt
  the original capture or prevent independent actions where recovery is possible.
- **NFR-005 Privacy:** Captures are processed locally. The MVP sends no capture
  content over the network.
- **NFR-006 Accessibility:** Controls have accessibility labels, keyboard focus,
  and sufficient contrast.
- **NFR-007 Compatibility:** The deployment target must support the selected
  ScreenCaptureKit APIs and is documented before the first release.
- **NFR-008 Observability:** Debug logging contains actionable state and errors
  but never logs image bytes or sensitive screen content.

## 5. Policy Precedence

After a successful capture, operations follow this order:

1. Produce one canonical in-memory capture result.
2. Copy it when Auto Copy is enabled.
3. Apply the configured save policy.
4. Apply the configured preview policy.
5. Record only the history metadata allowed by the retention policy.

Ask Every Time affects file persistence only. It must not delay clipboard copy.
Never preview and Never Save are independent settings.

## 6. MVP Acceptance Scenarios

- A region capture on a Retina display pastes at the expected pixel dimensions.
- A window capture includes the intended window and handles window shadows
  consistently.
- A full-screen capture chooses the correct display in a multi-monitor setup.
- Never Save leaves no persistent image file.
- Always Save creates a uniquely named file in the selected folder.
- Ask Every Time allows discard while the captured image remains pasteable.
- Auto Hide closes the preview after its configured duration.
- Denied Screen Recording permission produces a recovery path rather than a
  silent failure.
- Escape during selection produces no capture side effects.

## 7. Text Recognition (Copy Text)

Post-MVP, V2. The full Preview window, the Capture History window, and the
Annotation editor each offer a **Copy Text** action (⌘T in Preview and the
editor) that recognizes text in the capture with Apple Vision and places the
plain-text result on the clipboard. It is fully on-device — no network, nothing
leaves the machine — and runs only when the user invokes it, not on every
capture.

- Recognition reads the canonical capture image, not the fit-scaled preview.
- In the Annotation editor, recognition reads the rendered image, so a crop
  restricts the recognized text to the cropped region and a blur keeps the text
  it covers out of the result.
- A global **Capture Text** shortcut (default ⌃⇧T) runs the whole flow in one
  step: select a region, recognize its text, and place it on the clipboard —
  with no image on the clipboard, no saved file, no preview, and no history
  entry. The menu bar shows "Recognizing text…", then "Text copied to
  clipboard" or "No text found in selection".
- Success copies the recognized text and shows "Text copied"; the Preview window
  stays open so the user can also copy or annotate the image.
- A capture with no readable text shows "No text found" and leaves the clipboard
  untouched.
- Language is detected automatically; scripts supported by the OS Vision build
  (including Thai on macOS 14+) are recognized without configuration.
- Consistent with the privacy rules, recognized text is never logged.

## 8. Out of Scope for MVP

QR detection, pinning, scrolling capture, screen/GIF recording, cloud sync,
share links, and AI-assisted annotation are roadmap features and do not block
the first usable release.
