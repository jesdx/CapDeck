# CapDeck Coding Guidelines

## 1. General Principles

- Prefer clear, native Swift over clever abstractions.
- Keep the capture-to-clipboard path short and observable.
- Model product policies explicitly; avoid scattered boolean combinations.
- Add abstractions at system boundaries or when they make testing materially
  easier.
- Keep feature code close to the feature that owns it.

## 2. Swift

- Use Swift 6 and enable strict concurrency checks.
- Follow the Swift API Design Guidelines.
- Prefer structs and enums for immutable models and policy types.
- Mark UI-facing state and AppKit coordination with `@MainActor`.
- Use `async`/`await` and structured concurrency. Avoid detached tasks unless
  isolation and lifetime are deliberately documented.
- Avoid force unwraps, force casts, and `try!` in production code.
- Prefer early exits with `guard` when they make the happy path clearer.
- Use access control intentionally; default implementation details to `private`.
- Do not abbreviate names unless the abbreviation is a well-known platform term.

## 3. File and Type Organization

- Prefer one primary type per file and name the file after that type.
- Place SwiftUI screens and feature-specific subviews in their owning feature.
- Put reusable platform interactions behind focused services.
- Keep extensions small and name extension files as `Type+Capability.swift`.
- Avoid generic `Helpers.swift` or `Utilities.swift` dumping grounds.
- Create source directories only when they contain real code.

## 4. Architecture Boundaries

- Views render state and send user intent; they do not capture screens, write
  files, or mutate the pasteboard directly.
- Coordinators own workflow ordering and policy decisions.
- Services wrap one external system capability and do not present custom
  CapDeck UI. A platform-required system panel, such as `NSSavePanel`, is
  allowed only at the capability boundary.
- Feature presenters own custom AppKit panels and overlays. They translate user
  interaction into protocol dependencies but do not own workflow policy.
- Models must not depend on feature views.
- Framework-specific types should be converted at the service boundary when
  practical.
- Dependencies are injected through initializers. Avoid mutable global
  singletons for business behavior.

## 5. State and Errors

- Represent capture workflow state with an enum rather than unrelated flags.
- Treat cancellation separately from errors.
- Use typed, localized errors at domain boundaries.
- Preserve underlying errors for diagnostics without exposing sensitive screen
  information.
- Never silently ignore a failure that changes visible product behavior.

## 6. Concurrency and Performance

- Never perform image encoding or file I/O synchronously on the main actor.
- Avoid copying large image buffers unnecessarily.
- Check cancellation around delay, selection, capture, and processing work.
- Document actor isolation for services that hold mutable state.
- Measure before optimizing, but keep obvious high-volume image work out of
  SwiftUI view bodies.

## 7. SwiftUI and AppKit

- Use SwiftUI for settings, menus, and standard screens.
- Use AppKit where precise window level, focus, global event, or overlay control
  is required.
- Keep AppKit bridges narrow and isolate delegate ownership carefully.
- Provide accessibility labels and keyboard focus behavior for interactive
  controls.
- Keep previews lightweight and avoid stealing focus from the user's paste
  destination unless an editor is explicitly opened.

## 8. Testing

- New product policy and coordinate conversion code requires unit tests.
- Name tests by behavior, for example
  `askEveryTimeKeepsClipboardResultWhenSaveIsDeclined()`.
- Use Arrange-Act-Assert structure when it improves readability.
- Prefer deterministic fakes over timing-based waits.
- Add a regression test with every bug fix when the behavior is testable.
- Keep UI tests focused on critical user journeys; do not duplicate all unit
  behavior through UI automation.

## 9. Formatting and Linting

- Use SwiftFormat as the automatic formatter and SwiftLint for targeted static
  rules.
- Keep tool configuration in version control.
- Run formatting, linting, unit tests, and a Debug build before merging.
- Do not disable a lint rule inline without a short reason.

## 10. Documentation

- Public or non-obvious APIs require concise documentation comments.
- Comments explain why, constraints, or platform quirks—not what readable code
  already says.
- Record user-visible behavior in `PRODUCT_REQUIREMENTS.md` and architectural
  decisions in `ARCHITECTURE.md` or a future decision record.
- Update `TASKS.md` when work changes scope or status.

## 11. Git Practices

- Keep commits small, cohesive, and buildable where practical.
- Use imperative commit subjects, such as `Add region selection overlay`.
- Do not commit DerivedData, build products, user-specific Xcode state, signing
  secrets, or captured screenshots containing private data.
- Review the staged diff before committing.

## 12. Definition of Done

A change is done when:

- Required behavior and edge cases are implemented.
- Relevant tests pass.
- The CapDeck target builds without new warnings.
- Formatting and lint checks pass when configured.
- Accessibility and privacy effects have been considered.
- Product, architecture, and task documentation are updated when applicable.
