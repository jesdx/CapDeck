# Security Policy

## Supported versions

Only the latest released version of CapDeck receives security fixes.

| Version | Supported |
| ------- | --------- |
| 1.2.x (latest) | ✅ |
| older | ❌ |

## Reporting a vulnerability

Please report security issues **privately** — do not open a public issue.

- Preferred: open a [private security advisory](https://github.com/jesdx/CapDeck/security/advisories/new).
- Or email **capdeck@jesdx.com**.

Include the CapDeck version, your macOS version, steps to reproduce, and the
impact. Please do not attach screenshots that contain sensitive content. You can
expect an acknowledgement within about a week.

## How CapDeck handles your data

CapDeck is local-first, requires no account, and sends no analytics or
telemetry.

- **Captured images stay in memory.** They are written to disk only when you
  explicitly Save. There are no temporary image files.
- **Capture History is RAM-only** (newest 10, ~256 MiB budget) and is released
  when the app quits. "Never Save" creates no persistent image files.
- **No hidden caches.** CoreImage intermediate caching is disabled during
  annotation, and macOS application-state restoration is disabled so windows
  containing a capture are never snapshotted to disk.
- **Logs contain metadata only** — capture mode, pixel dimensions, and timing.
  Image content, file names, and window titles are never logged.

## Network and updates

- The only network connection CapDeck makes is to its software-update feed.
- Updates use [Sparkle](https://sparkle-project.org) over HTTPS with **EdDSA
  (ed25519) signature verification**: an update is installed only if it is
  signed by the project's private key, which never leaves the maintainer's
  Keychain. System profiling is disabled, so no system information is sent.

## Clipboard and Universal Clipboard

When you copy a capture, it is placed on the macOS **general pasteboard**. Be
aware that:

- any running app can read the general pasteboard;
- third-party clipboard managers may store a copy of the image;
- if **Universal Clipboard / Handoff** is enabled, macOS may sync the image to
  your other Apple devices.

This is inherent to a clipboard-first workflow and is not specific to CapDeck.
If a capture contains sensitive information, clear your clipboard afterward and
consider whether Universal Clipboard should be enabled.

## Code signing status

Release builds are currently **ad-hoc signed and not yet notarized** by Apple,
so Gatekeeper warns on first launch (see the README for how to open the app).
Update integrity does **not** depend on notarization — it is guaranteed by the
Sparkle EdDSA signature described above.
