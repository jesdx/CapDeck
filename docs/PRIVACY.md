# CapDeck Privacy

CapDeck is local-first and does not require an account.

- Screen content is captured only after the user invokes a capture command and
  chooses a region, window, or display.
- Capture pixels are not uploaded by CapDeck. The app contains no analytics,
  advertising, telemetry, cloud-sync, or share-link service.
- Clipboard output is written to the local macOS pasteboard. The destination
  application controls what happens after the user pastes it.
- **Never Save** creates no persistent image file.
- Capture History is session-only RAM storage. It retains at most 10 captures
  and approximately 256 MB of pixel buffers, evicts oldest captures first, can
  be cleared immediately, and is released when CapDeck quits.
- **Always Save**, **Ask Every Time**, and **Save As** write only to a location
  selected by the user. CapDeck stores a security-scoped bookmark solely to
  regain access to that selected folder.
- Debug logs contain workflow state, dimensions, timing, and error messages;
  they never contain image bytes or recognized screen text.
- Manual or opt-in automatic update checks contact CapDeck's public GitHub
  release feed. They send no capture content, analytics, or system profile.
  Downloads occur only after an update is available and the user approves it.

macOS Screen Recording permission can be revoked at any time in Privacy &
Security settings. CapDeck stops capture and presents a recovery path when the
permission is unavailable.
