# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Scopes: `Wiztchta.new(scope: "signup")` binds a challenge to one purpose, and
  `Wiztchta.verify/2` (or `Wiztchta.Plug`) must be given the same scope, otherwise it
  returns `{:error, :scope_mismatch}`. Matching is strict ("no scope" is its own value);
  atoms and strings are equivalent. Mismatches don't consume the token. Tokens issued
  by earlier versions count as unscoped.
- Session binding: challenges are tied to the visitor's session (a hash of the
  `protect_from_forgery` secret), so tokens can't be farmed in one session and used in
  another; mismatches return `{:error, :session_mismatch}` without consuming the token.
  Automatic wherever CSRF protection runs in the request (controllers); opt-in in
  LiveViews with `Wiztchta.session_binding/1` and `bind:`; `bind: false` opts out.

### Upgrade notes

- Controller forms that were already open when you deploy (rendered by 0.2, so
  unbound) return `:session_mismatch` until they expire (`max_age`, 5 minutes by default).
- LiveView forms that post to a controller (`phx-trigger-action`) must create their
  challenge with `bind: Wiztchta.session_binding(session)`, or use `bind: false`.
- Calls to `Wiztchta.new/1` and `verify/2` in controllers now bind too; pass
  `bind: false` to both if a token is created and verified in different sessions.

## [0.2.0] - 2026-11-13

### Added

- Honeypot trap field, rendered by `<.wiztchta>` and checked first by `Wiztchta.verify/2`,
  which returns the new `{:error, :honeypot}`. Enabled by default; configure with
  `:honeypot` and `:honeypot_field`. Forms rendered without the field still verify.
- Minimum fill time: `Wiztchta.verify/2` returns `{:error, :too_fast}` for submissions
  made less than `:min_time` seconds (default `2`) after the challenge was created. The
  issue time is stored in the encrypted token; too-fast attempts don't consume it.
- Submit guard: forms can't be submitted while their proof-of-work is still solving.
  Submit buttons are disabled (`data-wiztchta-disabled`) and submit events are blocked
  before LiveView or the browser handle them; Enter in a text field is covered too.
- The proof-of-work `:difficulty` is validated (integer 1–32); README documents
  measured solving times to help choose it per form.

### Fixed

- The proof-of-work `data-state` no longer resets to `pending` when LiveView
  re-renders the component; it now lives on `.wiztchta-pow-box`.

### Upgrade notes

- Set `config :wiztchta, min_time: 0` in `config/test.exs`; tests submit forms
  instantly and would otherwise get `{:error, :too_fast}`.
- Consider `min_time: 0` for login forms, which password managers fill instantly.
- Tokens issued by 0.1.x have no issue time and skip the minimum fill time check.
- CSS targeting `data-state` should use `.wiztchta-pow-box[data-state=...]`
  (descendant selectors such as `.wiztchta [data-state=solved]` keep working).

### Changed

- Repository moved to https://github.com/darth-jorge/wiztchta (package links and docs source links updated).

## [0.1.0] - 2026-11-12

### Added

- `<.wiztchta>` form component for controllers and LiveViews.
- `Wiztchta.new/1` and `Wiztchta.verify/2` with encrypted, expiring, single-use tokens.
- `Wiztchta.Challenge` behaviour with built-in proof-of-work (default) and math challenges.
- `Wiztchta.Store` behaviour for replay protection, with an in-memory ETS default.
- `Wiztchta.Plug` for verifying submissions in controller actions.
- Browser runtime (`import { Hooks, init } from "wiztchta"`) with a LiveView hook.

[Unreleased]: https://github.com/darth-jorge/wiztchta/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/darth-jorge/wiztchta/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/darth-jorge/wiztchta/releases/tag/v0.1.0
