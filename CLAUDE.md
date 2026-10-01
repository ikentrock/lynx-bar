# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

lynx-bar is a fork of [Ice](https://github.com/jordanbaird/Ice) (remote `upstream`), a macOS menu bar manager written in Swift/SwiftUI + AppKit. Targets macOS 14+ (the app relies on APIs introduced in 14; earlier versions are not supported). Licensed GPL-3.0.

The code still uses upstream identifiers: target/scheme `Ice`, bundle ID `com.jordanbaird.Ice`, development team `K2ATHQPJDP`, and the Sparkle feed `SUFeedURL`/`SUPublicEDKey` in `Ice/Info.plist` point at upstream releases. Change these deliberately if the fork is to ship its own builds — otherwise a fork build would auto-update to upstream Ice.

## Commands

There is a single Xcode project with one scheme (`Ice`) and **no test target**. Building needs full Xcode, not just the Command Line Tools (`xcode-select -p` must point inside `Xcode.app`).

```sh
# Build (ad-hoc signing avoids needing upstream's dev team)
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build

# Lint — CI runs exactly this on every Swift change and fails on warnings
swiftlint --strict          # brew install swiftlint
```

SPM dependencies (resolved via the project, not a Package.swift): Sparkle (updates), LaunchAtLogin-Modern, AXSwift, CompactSlider, Ifrit (fuzzy search).

## Lint conventions that CI enforces

`.swiftlint.yml` is strict and opinionated; the non-obvious rules:
- Every file must start with the header `//\n//  <FileName>.swift\n//  Ice\n//`.
- 4-space indentation, no tabs; mandatory trailing commas in multiline collections.
- `force_unwrapping` and implicitly unwrapped optionals are errors.
- `@objc` must be immediately followed by `dynamic` where both are used.

## Architecture

**Entry and state.** `Main/IceApp.swift` swizzles `NSSplitViewItem`, runs `MigrationManager.migrateAll` (versioned migrations of persisted defaults — add a new `migrateX_Y_Z` when changing stored formats), and hands an `AppState` to `AppDelegate`. `Main/AppState.swift` is the `@MainActor` hub: it lazily owns every manager (`MenuBarManager`, `MenuBarItemManager`, `MenuBarAppearanceManager`, `EventManager`, `PermissionsManager`, `SettingsManager`, `UpdatesManager`, `UserNotificationManager`, `MenuBarItemImageCache`, `MenuBarItemSpacingManager`, `HotkeyRegistry`). Managers take `appState` in their initializer and are wired up in `AppState.performSetup()`; manager `objectWillChange` is forwarded so SwiftUI views observe `AppState`. Changes are propagated with Combine publishers stored in `cancellables`.

**How hiding works.** Ice does not remove other apps' status items. It owns three `NSStatusItem`s (`MenuBar/ControlItem/ControlItem.swift`: `iceIcon` "SItem", `hidden` "HItem", `alwaysHidden` "AHItem") that act as section dividers. To hide a section, the divider's length is set to `Lengths.expanded` (10,000 pt), pushing everything to its left off-screen; showing restores `variableLength`. `MenuBar/MenuBarSection.swift` models the visible / hidden / always-hidden sections, including rehide timers and whether to show items in the "Ice Bar" panel (a separate bar below the menu bar, for notched MacBooks).

**Moving and clicking other apps' items.** `MenuBar/MenuBarItems/MenuBarItemManager.swift` rearranges items by synthesizing ⌘-drag `CGEvent`s and posting them through event taps (`Events/EventTap.swift`), then waiting until the item's window frame changes. It also caches the per-section item list, temporarily shows hidden items (move, click, move back), and enforces control-item ordering. This code is timing-sensitive: it waits for mouse/modifier inactivity and uses timeouts (`Utilities/TaskTimeout.swift`).

**Private APIs.** `Bridging/` wraps private CoreGraphics/SkyLight (`CGS*`) functions, declared via `@_silgen_name` in `Bridging/Shims/Private.swift`. They are used for window lists, spaces/fullscreen detection, and connection properties. Use the `Bridging` enum rather than calling shims directly.

**Permissions.** Accessibility is required (event posting/AX). Screen Recording is optional and only drives item images (`MenuBarItemImageCache`, `Utilities/ScreenCapture.swift`). The app is not sandboxed (`Ice/Ice.entitlements`).

**Other areas.** `Events/` holds global/local event monitors that feed show-on-hover, show-on-click and show-on-scroll. `Hotkeys/` provides the registry and recorder. `MenuBar/Appearance/` draws the tint, shadow, border and custom shapes as an overlay panel. `MenuBar/Search/` is the item search panel. `MenuBar/Spacing/` changes system item spacing through defaults. `Settings/` holds the SwiftUI settings panes plus the `SettingsManagers` that persist to `UserDefaults` via `Utilities/Defaults.swift`. `UI/` holds shared SwiftUI components (`IceBar`, `LayoutBar` drag-and-drop arranger, pickers).

`FREQUENT_ISSUES.md` documents known user-facing problems and workarounds.
