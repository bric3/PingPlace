# Contributing

## Development setup

PingPlace is a macOS app built directly with `swiftc` and `make`.

Useful commands:

```bash
make test
make build
make debug-build
```

Artifacts:

- `PingPlace.app`
- `.build/`

## Tests

Run the local behavior test suite with:

```bash
make test
```

The GitHub Actions workflow runs the same command on pull requests and on pushes to `master`.

## Debug build and logs

To diagnose notification placement issues, especially around wake, login, and screen topology changes, use the debug build:

```bash
make debug-build
open PingPlace.app
```

The debug build enables verbose tracing by default and writes logs to:

```bash
~/Library/Logs/PingPlace/debug.log
```

You can override runtime debug mode with:

```bash
defaults write com.grimridge.PingPlace debugMode -bool true
defaults write com.grimridge.PingPlace debugMode -bool false
```

Useful log commands:

```bash
tail -f ~/Library/Logs/PingPlace/debug.log
rg "Moved notification|Recovery retry|placeholder follow-up" ~/Library/Logs/PingPlace/debug.log
```

### Menu preview mode

To inspect the menu UI without starting the Accessibility/event-handling backend, launch a separate preview instance:

```bash
open -n PingPlace.app --args --menu-preview
```

Preview mode:

- shows the menu and 3x3 position picker
- does not request Accessibility permissions
- does not move notifications
- does not persist picker selections
- replaces any previous preview instance

## Build metadata

Builds generate metadata in `.build/BuildInfo.generated.swift` at build time. The startup log includes:

- git commit
- dirty or clean working tree state
- UTC build timestamp
- source fingerprint

This is meant to distinguish local debug builds, including builds created from uncommitted changes.

## Code signing

By default, local builds use ad-hoc signing (`-`).

That is enough to run the app locally, but macOS Accessibility permissions may need to be re-approved for rebuilt binaries.

If you want more stable local signing, save a codesign identity:

```bash
make save-codesign-identity CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)"
```

To clear it:

```bash
make clear-codesign-identity
```

The local identity is stored in `.codesign_identity`, which is intentionally ignored by git.

## Scope of tests

The current test suite focuses on extracted, testable logic:

- notification move policy
- Notification Center panel state policy
- retry and follow-up recovery behavior
- placement and cache behavior
- screen resolution policy
- tree traversal

The suite does not fully cover real macOS Accessibility behavior, Notification Center timing, or AppKit subscription wiring. Those still need live verification on macOS.
