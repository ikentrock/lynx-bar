# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Lynx Bar is a fork of [Ice](https://github.com/jordanbaird/Ice) (remote `upstream`), a macOS menu bar manager written in Swift/SwiftUI + AppKit. It is based on upstream's unreleased `macos-26` branch (merged 2026-10-02). Targets macOS 14+ (the app relies on APIs introduced in 14; earlier versions are not supported). Licensed GPL-3.0.

The app is `Lynx Bar.app`, bundle ID `com.ikentrock.LynxBar`; its helper is `com.ikentrock.LynxBar.MenuBarItemService`. The Xcode target, scheme and Swift module are still named `Ice`, as are most type names (`IceBar` is the "Lynx Shelf") and the `//  Ice` file headers — an internal rename is planned separately. Identity and signing live in `Config/Base.xcconfig`. Updates are off: there is no `SUFeedURL`, so Sparkle never starts. Stored defaults keys keep their upstream names (`IceIcon`, `UseIceBar`, `Ice.ControlItem.*`); never rename them.

Design docs and plans live in `docs/superpowers/`.

## Commands

There is a single Xcode project with one app scheme (`Ice`) and **no test target**. Building needs full Xcode, not just the Command Line Tools (`xcode-select -p` must point inside `Xcode.app`).

```sh
# Build (signing comes from Config/Base.xcconfig: ad-hoc by default)
xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build

# Script tests (standalone swiftc programs under Scripts/Tests)
Scripts/run-tests.sh
LYNX_TEST_CERT=<certificate SHA-1> Scripts/run-tests.sh   # also tests certificate signing

# Lint — CI runs exactly this on every Swift change and fails on warnings
swiftlint --strict          # brew install swiftlint
```

To sign with a certificate, create the gitignored `Config/Local.xcconfig` with `CODE_SIGN_IDENTITY = <certificate name>` (see `Config/Local.xcconfig.example`). Builds without a team need `Config/LynxBar.entitlements` (`disable-library-validation`), because the hardened runtime otherwise refuses to load the app's own debug dylib and frameworks.

SPM dependencies are resolved via the project (no Package.swift): Sparkle, LaunchAtLogin-Modern, AXSwift, Ifrit, Semaphore. CompactSlider is vendored in `Packages/CompactSlider` with a patch for Xcode 27 (see its `VENDORED.md`).

## Lint conventions that CI enforces

`.swiftlint.yml` is strict, opinionated, and only lints `LynxBar/`; the non-obvious rules:
- Every file must start with the header `//\n//  <FileName>.swift\n//  Ice\n//` (files in `Shared/` and `MenuBarItemService/` use their folder name instead).
- 4-space indentation, no tabs; mandatory trailing commas in multiline collections.
- `force_unwrapping` and implicitly unwrapped optionals are errors.
- `@objc` must be immediately followed by `dynamic` where both are used.

## Architecture

**Entry and state.** `Main/IceApp.swift` declares the scenes; `Main/AppDelegate.swift` runs `IceSettingsImporter` (one-time copy of Ice's defaults), then creates `AppState`, then runs `MigrationManager.migrateAll()` (versioned migrations in `Utilities/Migration.swift` — add a new `migrateX_Y_Z` when changing stored formats). `Main/AppState.swift` is the `@MainActor` hub owning `settings`, `permissions`, `navigationState`, `menuBarManager`, `appearanceManager`, `spacingManager`, `itemManager`, `imageCache`, `hidEventManager`, `updatesManager` and `userNotificationManager`; managers are wired up in its `setupTask`, and their `objectWillChange` is forwarded so SwiftUI views observe `AppState`.

**How hiding works.** Lynx Bar does not remove other apps' status items. It owns three `NSStatusItem`s (`MenuBar/ControlItem/ControlItem.swift`, identifiers `Ice.ControlItem.Visible/Hidden/AlwaysHidden`) that act as section dividers. To hide a section, the divider's length is set to `Lengths.expanded` (10,000 pt), pushing everything to its left off-screen. `MenuBar/MenuBarSection.swift` models the visible / hidden / always-hidden sections, including rehide timers and whether to show items in the Lynx Shelf (`MenuBar/IceBar/`, a panel below the menu bar).

**macOS 26 item identity.** On macOS 26 every menu bar item window is owned by Control Center, so the owning app can't be read from the window list. The `MenuBarItemService` XPC helper (`MenuBarItemService/`, code shared via `Shared/`) maps windows to their source apps using Accessibility (`SourcePIDCache`). App and helper talk over the C XPC API and trust each other only when signed with the same certificate and the expected identifier (`Shared/Services/PeerCodeRequirement.swift`, `MenuBarItemServiceIdentity.swift`). If the helper is refused, `MenuBarItemManager.helperFailureReason` is set, the UI shows a message, and items are neither cached nor moved.

**Moving and clicking other apps' items.** `MenuBar/MenuBarItems/MenuBarItemManager.swift` rearranges items by synthesizing ⌘-drag `CGEvent`s and posting them through event taps (`Events/EventTap.swift`), then waiting until the item's window frame changes. It also caches the per-section item list, temporarily shows hidden items (move, click, move back), and enforces control-item ordering. This code is timing-sensitive.

**Private APIs.** `Shared/Bridging/` wraps private CoreGraphics/SkyLight (`CGS*`) functions, declared via `@_silgen_name` in `Shared/Bridging/Shims.swift`. Use the `Bridging` enum rather than calling shims directly.

**Permissions.** Accessibility is required (event posting/AX). Screen Recording is optional and drives item images and the Lynx Shelf (`MenuBarItemImageCache`, `Utilities/ScreenCapture.swift`). The app is not sandboxed.

**Other areas.** `Events/` holds global/local event monitors that feed show-on-hover, show-on-click and show-on-scroll. `Hotkeys/` provides the registry and recorder. `MenuBar/Appearance/` draws the tint, shadow, border and custom shapes as an overlay panel. `MenuBar/Search/` is the item search panel. `MenuBar/Spacing/` changes system item spacing through defaults. `MenuBar/LayoutBar/` is the drag-and-drop arranger. `Settings/` holds the SwiftUI settings panes and `Settings/Models/`, which persist to `UserDefaults` via `Utilities/Defaults.swift`. `UI/` holds shared SwiftUI components. Artwork is rendered from SVG sources with `swift Resources/Artwork/render.swift`.

`FREQUENT_ISSUES.md` documents known user-facing problems and workarounds.

## Debugging

- In zsh, `log` is a shell builtin; use `/usr/bin/log show --predicate 'subsystem == "com.ikentrock.LynxBar"'` (add `--info --debug` for lower levels). The helper logs under `com.ikentrock.LynxBar.MenuBarItemService`.
- Ad-hoc builds lose their Accessibility/Screen Recording grants on every rebuild; sign with a certificate so grants persist.
- Test builds that share the bundle ID share defaults and permission entries; give throwaway builds a different bundle ID and name.
