# Contributing to CapDeck

Thanks for your interest in improving CapDeck! This document explains how to
build, test, and submit changes.

## Requirements

- macOS 14 or newer (required by `SCScreenshotManager`)
- Xcode 16 or newer with the macOS SDK
- [SwiftFormat](https://github.com/nicklockwood/SwiftFormat) and
  [SwiftLint](https://github.com/realm/SwiftLint) for style checks

Dependencies (currently [Sparkle](https://sparkle-project.org)) are resolved
automatically through Swift Package Manager when you open the project.

## Build & test

This is an Xcode project (there is no `Package.swift`). Prefer `xcodebuild`:

```sh
# Build (Debug)
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck \
  -destination 'platform=macOS' build

# Run all unit tests
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck \
  -destination 'platform=macOS' -only-testing:CapDeckTests test

# Run a single test (target/class/method)
xcodebuild -project CapDeck.xcodeproj -scheme CapDeck -destination 'platform=macOS' \
  -only-testing:CapDeckTests/CapDeckTests/yourTestMethodName test
```

To run the app: open the project in Xcode, select the `CapDeck` scheme and a
local Mac destination, and Run. The first capture triggers the macOS Screen
Recording permission prompt.

## Style

- SwiftFormat (`.swiftformat`) — 4-space indent, `before-first` argument
  wrapping, trailing commas.
- SwiftLint (`.swiftlint.yml`) — note that `force_unwrapping` is enabled;
  force unwraps and `try!` are **not** allowed in production code.

Run both before opening a PR:

```sh
swiftformat .
swiftlint
```

## Architecture

Please read [`ARCHITECTURE.md`](ARCHITECTURE.md) before making structural
changes. The layering is intentional and strict:

> Views render state and emit intent; Coordinators own workflow ordering and
> product policy; Services wrap one system capability. Native presenters live
> under each feature. Models never depend on views. Dependencies are injected
> through initializers.

Coordinate conversion (`CapDeck/Features/Selection/SelectionGeometry.swift`) is
the highest-risk area and **must** keep its unit tests green for any change.

## Pull requests

1. Fork and create a topic branch off `main`.
2. Add a regression test with every testable bug fix. Name tests by behavior
   (e.g. `askEveryTimeKeepsClipboardResultWhenSaveIsDeclined`).
3. Make sure `xcodebuild … test`, SwiftFormat, and SwiftLint all pass.
4. Keep changes focused; update the relevant docs (`PRODUCT_REQUIREMENTS.md`,
   `TASKS.md`, `CHANGELOG.md`) when behavior changes.
5. Open the PR with a clear description of the behavior change and why.

## Reporting bugs

Open an issue with your macOS version, steps to reproduce, and what you
expected. Please do **not** include screenshots containing sensitive content —
CapDeck never logs or transmits image content, and neither should bug reports.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE) that covers this project.
