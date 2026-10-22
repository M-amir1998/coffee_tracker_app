# ADR 0001: Flutter with Riverpod and GoRouter

Status: accepted (2026-10-22)

## Context

The app has to run on Android, iOS, the web, Windows, macOS and Linux, be
maintained by a small team, and behave the same everywhere, especially when it
shows money.

## Decision

- One Flutter code base (stable channel, pinned in CI) for every platform.
- Riverpod 3 for state: providers are testable without widgets, can be
  overridden in tests, and `autoDispose.family` fits "one read model per group
  and period".
- GoRouter for navigation: URL-based routes are required for the web (deep
  links, invitation links, browser history) and redirects express the
  authentication rules in one place.
- Material 3 with custom tokens rather than a third-party design kit.

## Consequences

- Platform-specific code is limited to file export (browser download, desktop
  save dialog, mobile share sheet) and the runner configuration.
- Flutter web output is larger than a hand-written web app; acceptable for an
  internal tool. The web build ships a web app manifest, so supporting browsers
  can install it like an app.
- Desktop builds on Windows need Developer Mode (plugin symlinks).
