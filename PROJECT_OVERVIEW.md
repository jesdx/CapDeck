# CapDeck Project Overview

## Product Vision

CapDeck is a lightweight, fast, native macOS screenshot application built for
clipboard-first workflows. It removes the unnecessary steps between capturing
something on screen and pasting it into an AI assistant, chat application, or
document.

### Name

**CapDeck** combines **Cap** (capture) with **Deck** (a collected set, like a
deck of cards or a slide deck). The name reflects the product's two connected
ideas: capturing an image quickly and keeping recent captures together as a
useful visual collection. It is short, modern, and leaves room for the product
to grow beyond a single screenshot action.

The primary workflow is:

```text
Capture -> Clipboard -> Paste -> Done
```

Saving, previewing, and editing are optional actions rather than mandatory
steps.

## Problem

The built-in macOS screenshot experience is general-purpose. CapDeck is
opinionated around screenshots that are temporary and need to be pasted
immediately into tools such as ChatGPT, Codex, Claude, Gemini, Slack, Discord,
Messenger, or documentation.

CapDeck addresses three recurring problems:

- Preview behavior should be predictable.
- Temporary screenshots should not always create permanent files.
- A completed capture should be ready on the clipboard immediately.

## Target User

The initial target user is the project owner and other keyboard-oriented macOS
users who frequently share screenshots with AI and communication tools. A
public or commercial release is optional and is not an MVP success criterion.

## Product Principles

- Native first
- Clipboard first
- Keyboard first
- Fast and predictable
- Minimal but configurable
- Privacy first and local first
- No account required
- AI-workflow friendly

## Core Experience

```text
Global shortcut
    -> Choose or infer capture mode
    -> Capture screen content
    -> Copy image to clipboard
    -> Optionally save
    -> Optionally show preview
    -> Finish
```

The dedicated AI Workflow Mode uses a short-lived preview:

```text
Capture -> Clipboard -> Thumbnail for 2 seconds -> Auto-close -> Paste into AI
```

## MVP Scope

The MVP includes:

- Region, window, and full-screen capture
- Multi-monitor and Retina display support
- Automatic clipboard copy
- Never Save, Always Save, and Ask Every Time policies
- Configurable destination, format, filename pattern, and delay
- Always, Never, and Auto Hide preview policies
- Basic annotation: crop, arrow, rectangle, text, blur, undo, and redo
- Menu bar commands and configurable global shortcuts
- Launch-at-login and menu bar visibility settings
- Local settings and local file handling

## Deferred Scope

The following capabilities are intentionally deferred:

- V2: OCR, QR detection, floating images, pinned images, and improved annotation
- V3: scrolling screenshots, screen recording, GIF recording, cloud sync,
  share links, and AI-assisted annotation

Scrolling capture is an important product goal, but it is not required to ship
the first usable MVP.

## Technology Direction

- Swift 6
- SwiftUI with AppKit integration
- ScreenCaptureKit, CoreGraphics, and CoreImage
- Vision for future OCR
- AVFoundation for future recording
- FileManager and UserDefaults initially; SwiftData only when richer history is
  needed
- Swift Package Manager
- KeyboardShortcuts, SwiftLint, and SwiftFormat where they provide clear value

## Success Criteria

CapDeck succeeds when a user can invoke a shortcut, capture the intended
content, and paste a correct high-resolution image without opening Finder or a
separate editor. The app should behave consistently across capture modes,
displays, preview policies, and save policies.

## Current Milestone

V1.2.2 provides the native capture-to-clipboard path, multi-display fidelity,
preview, save policies, complete annotation toolset, bounded session-only
Capture History, keyboard/accessibility paths, stable permission recovery,
automated quality gates, local release packaging, and signed software update
checks. V1 engineering is complete; the owner-review compatibility matrix is maintained in
[STATUS.md](STATUS.md).

## Project Documents

- [PRODUCT_REQUIREMENTS.md](PRODUCT_REQUIREMENTS.md) defines product behavior.
- [ARCHITECTURE.md](ARCHITECTURE.md) defines system boundaries and technical
  direction.
- [CODING_GUIDELINES.md](CODING_GUIDELINES.md) defines implementation standards.
- [TASKS.md](TASKS.md) tracks delivery work and roadmap progress.
- [STATUS.md](STATUS.md) records the current completion percentages,
  verification snapshot, and recommended next milestone.
