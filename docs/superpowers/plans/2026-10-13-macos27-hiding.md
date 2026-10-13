# macOS 27 Hiding (Round A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make hiding and showing the hidden and always-hidden sections work on macOS 27. Item-list features say "not supported on macOS 27 yet" instead of hanging on "Loading…".

**Architecture:** On macOS 27 a section divider hides its section by being exactly as wide as the free space between the app menus and the visible items. Whatever doesn't fit goes into the system's `«` overflow. A pure calculator (`HostedHidingWidth`) does the arithmetic. A small Accessibility reader (`MenuBarAgentLayout`) reads `MenuBarAgent`'s slots to find our own dividers. `MenuBarItemManager` measures and publishes widths, and `ControlItem` applies them. Everything new sits behind `#available(macOS 27.0, *)`, checked before the existing macOS 26 checks.

**Tech Stack:** Swift 5 / SwiftUI + AppKit, AXSwift, Combine. Script tests compiled by `Scripts/run-tests.sh` with `swiftc`.

**Spec:** `docs/superpowers/specs/2026-10-13-macos27-hiding-design.md`

## Global Constraints

- macOS 14–26 behaviour must not change: all new behaviour is behind `#available(macOS 27.0, *)`, placed before any `#available(macOS 26.0, *)` check it shares a code path with.
- Every new file in `LynxBar/` starts with the header `//\n//  <FileName>.swift\n//  LynxBar\n//`.
- `swiftlint --strict` must pass: 4-space indentation, trailing commas in multiline collections, no `!` force unwraps, no implicitly unwrapped optionals.
- Stored defaults keys keep their names (`UseIceBar` etc.); never rename them. `Scripts/check-names.sh` must pass.
- No test target exists; tests are standalone programs in `Scripts/Tests/<Name>/main.swift` run by `Scripts/run-tests.sh`.
- Build: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build` (needs full Xcode). Source folders are synchronized groups, so new files under `LynxBar/` are picked up without editing the project file.
- Constants: margin 8 pt, agent padding 16 pt, reapply threshold 8 pt, length cap `floor(screenWidth / 2) - 16`, re-measure delay 600 ms, at most 3 resets in a row.
- User-facing message on 27: `Showing menu bar items isn't supported on macOS 27 yet.`
- Ported logic credits IceMelt (https://github.com/pnikolaidis/icemelt, PR #46, GPL-3.0) in a doc comment and the commit message.

## Review Focus

1. **Long app menus while hidden.** Switching to Mail or Xcode while hidden must not leave the items showing for good. The divider may flash once (reset and re-measure) but must end up hidden again. Task 4 manual check, plus `HostedHidingWidth` tests for a shrinking room.
2. **Starting from the broken state.** The divider sits outside the bar (`y=1084`) on launch. It must come back into the bar and hide. Recovery is covered by the slot-missing path in Task 4 and tested by hand.
3. **Reflow loop.** Applying a width moves items, which triggers another measurement. Changes under 8 pt must be ignored, and 3 failed resets must stop the loop. `shouldApply` and the reset-limit tests in Task 1 cover this.
4. **Overflowed items listed in the tree.** Hidden items piled up at `«` must not count as "in the bar" when the divider has no slot. A `visibleFrom` test in Task 1 covers this.
5. **Section shown with no divider style.** `sectionDividerStyle == .noDivider` gives the divider length 0, so it may have no slot while shown. That must not trigger a reset: resets happen only while the section is hidden. Tested by hand in Task 4.

---

### Task 1: `HostedHidingWidth` calculator with script test

**Files:**
- Create: `LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift`
- Create: `Scripts/Tests/HostedHidingWidth/main.swift`
- Modify: `Scripts/run-tests.sh` (add build/run lines before `../Scripts/check-names.sh`)

**Interfaces:**
- Produces (all `static`, on `enum HostedHidingWidth`, importing only `CoreGraphics`):
  - `margin: CGFloat = 8`, `padding: CGFloat = 16`, `threshold: CGFloat = 8`, `maxResets = 3`
  - `regionLeft(applicationMenuMaxX: CGFloat, notchMaxX: CGFloat?) -> CGFloat`
  - `width(visibleFrom: CGFloat, regionLeft: CGFloat) -> CGFloat`
  - `length(width: CGFloat?, screenWidth: CGFloat) -> CGFloat`
  - `shouldApply(old: CGFloat?, new: CGFloat) -> Bool`
  - `visibleFrom(dividerSlot: CGRect?, otherSlots: [CGRect], chevron: CGRect?) -> CGFloat?`
  - `slot(forWindowFrame: CGRect, in ownSlots: [CGRect]) -> CGRect?`
  - `shouldReset(resetCount: Int) -> Bool`

- [ ] **Step 1: Write the failing test**

Create `Scripts/Tests/HostedHidingWidth/main.swift`:

```swift
//
//  main.swift
//  Tests
//

import CoreGraphics
import Foundation

// MARK: regionLeft

expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 533, notchMaxX: nil) == 549,
    "region starts after the app menu plus the agent's padding"
)
expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 400, notchMaxX: 820) == 836,
    "region starts after the notch when the notch is further right"
)
expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 900, notchMaxX: 820) == 916,
    "region starts after the app menu when it passes the notch"
)

// MARK: width

expect(
    HostedHidingWidth.width(visibleFrom: 1600, regionLeft: 549) == 1043,
    "width is the room less the margin"
)
expect(
    HostedHidingWidth.width(visibleFrom: 555, regionLeft: 549) == 0,
    "room smaller than the margin gives zero"
)
expect(
    HostedHidingWidth.width(visibleFrom: 500, regionLeft: 549) == 0,
    "negative room gives zero"
)

// MARK: length

expect(
    HostedHidingWidth.length(width: 600, screenWidth: 1920) == 584,
    "length is the width less the agent's padding"
)
expect(
    HostedHidingWidth.length(width: 1043, screenWidth: 1920) == 944,
    "length is capped at half the display less the padding"
)
expect(
    HostedHidingWidth.length(width: nil, screenWidth: 1920) == 944,
    "no measurement uses the cap"
)
expect(
    HostedHidingWidth.length(width: 10, screenWidth: 1920) == 0,
    "a width under the padding gives zero, never negative"
)
expect(
    HostedHidingWidth.length(width: 2000, screenWidth: 1801) == 884,
    "the cap rounds half an odd display width down"
)

// MARK: shouldApply

expect(HostedHidingWidth.shouldApply(old: nil, new: 500), "the first measurement is applied")
expect(!HostedHidingWidth.shouldApply(old: 500, new: 507.9), "changes under 8 pt are ignored")
expect(HostedHidingWidth.shouldApply(old: 500, new: 508), "changes of 8 pt are applied")
expect(HostedHidingWidth.shouldApply(old: 500, new: 420), "a shrinking room is applied")

// MARK: visibleFrom

let divider = CGRect(x: 684, y: 0, width: 916, height: 30)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: divider, otherSlots: [], chevron: nil) == 1600,
    "a divider in the bar bounds the visible items with its right edge"
)
let piledUp = [
    CGRect(x: 562, y: 0, width: 38, height: 30),
    CGRect(x: 553, y: 0, width: 47, height: 30),
]
let onBar = [
    CGRect(x: 608, y: 0, width: 36, height: 30),
    CGRect(x: 1600, y: 0, width: 32, height: 30),
]
let chevron = CGRect(x: 583, y: 1, width: 18, height: 28)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: piledUp + onBar, chevron: chevron) == 608,
    "without a divider slot, the leftmost item right of the chevron bounds the room"
)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: onBar, chevron: nil) == 608,
    "without a chevron, every item counts"
)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: [], chevron: nil) == nil,
    "an empty bar can't be measured"
)

// MARK: slot matching

let ownSlots = [
    CGRect(x: 1564, y: 0, width: 36, height: 30),
    CGRect(x: 1598, y: 0, width: 35, height: 30),
]
expect(
    HostedHidingWidth.slot(forWindowFrame: CGRect(x: 1564, y: 1049, width: 36, height: 33), in: ownSlots)
        == ownSlots[0],
    "a slot matches the window with the same x and width"
)
expect(
    HostedHidingWidth.slot(forWindowFrame: CGRect(x: 684, y: 1049, width: 1016, height: 33), in: ownSlots) == nil,
    "a dropped divider has no slot even though its window claims a place"
)

// MARK: reset limit

expect(HostedHidingWidth.shouldReset(resetCount: 0), "the first reset is allowed")
expect(HostedHidingWidth.shouldReset(resetCount: 2), "the third reset is allowed")
expect(!HostedHidingWidth.shouldReset(resetCount: 3), "a fourth reset in a row is refused")

finishTests("HostedHidingWidth")
```

Add to `Scripts/run-tests.sh`, directly above `../Scripts/check-names.sh || failed=1`:

```sh
build HostedHidingWidth ../LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift
run HostedHidingWidth

```

- [ ] **Step 2: Run the test to confirm it fails**

Run: `Scripts/run-tests.sh`
Expected: compile error, `no such file or directory: '../LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift'`.

- [ ] **Step 3: Write the implementation**

Create `LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift`:

```swift
//
//  HostedHidingWidth.swift
//  LynxBar
//

import CoreGraphics

/// Calculations for hiding a section on macOS 27, where the menu bar is
/// hosted by `MenuBarAgent`.
///
/// macOS 27 hides an item only by moving it into its own "Show Hidden Menu
/// Bar Items" overflow when it doesn't fit. A divider hides its section by
/// being just wide enough that the section no longer fits. Too narrow, and the
/// section's leading items stay visible. Too wide, and the system drops the
/// divider itself. It also drops any item wider than half the display.
///
/// Ported from IceMelt (https://github.com/pnikolaidis/icemelt, PR #46), GPL-3.0.
enum HostedHidingWidth {
    /// Space left between the region's start and the hidden items. It must be
    /// narrower than any item, or the section's last item stays in the bar.
    static let margin: CGFloat = 8

    /// The padding `MenuBarAgent` adds around an item's length.
    static let padding: CGFloat = 16

    /// Width changes smaller than this are ignored, since every change
    /// reflows the bar.
    static let threshold: CGFloat = 8

    /// How many times in a row a dropped divider is reset before giving up.
    static let maxResets = 3

    /// Returns where the agent's item area begins: after the application
    /// menu, or after the notch if that's further right.
    static func regionLeft(applicationMenuMaxX: CGFloat, notchMaxX: CGFloat?) -> CGFloat {
        max(applicationMenuMaxX, notchMaxX ?? applicationMenuMaxX) + padding
    }

    /// Returns how wide a divider must be to hide everything between the
    /// region's start and `visibleFrom`.
    static func width(visibleFrom: CGFloat, regionLeft: CGFloat) -> CGFloat {
        max(visibleFrom - regionLeft - margin, 0)
    }

    /// Returns the status item length for a measured width, capped so the
    /// system doesn't drop the divider. With no measurement, uses the cap.
    static func length(width: CGFloat?, screenWidth: CGFloat) -> CGFloat {
        let cap = (screenWidth / 2).rounded(.down) - padding
        guard let width else {
            return cap
        }
        return min(max(width - padding, 0), cap)
    }

    /// Returns whether a new width differs enough from the old one to apply.
    static func shouldApply(old: CGFloat?, new: CGFloat) -> Bool {
        guard let old else {
            return true
        }
        return abs(old - new) >= threshold
    }

    /// Returns where the items that must stay visible begin.
    ///
    /// - Parameters:
    ///   - dividerSlot: The divider's slot in the agent's layout, or `nil` if
    ///     the divider isn't in the bar.
    ///   - otherSlots: Every other item's slot.
    ///   - chevron: The overflow button's frame, if it's shown. Overflowed
    ///     items are listed piled up against it and aren't in the bar.
    static func visibleFrom(dividerSlot: CGRect?, otherSlots: [CGRect], chevron: CGRect?) -> CGFloat? {
        if let dividerSlot {
            return dividerSlot.maxX
        }
        let inBar = otherSlots.filter { slot in
            guard let chevron else {
                return true
            }
            return slot.minX >= chevron.maxX
        }
        return inBar.map(\.minX).min()
    }

    /// Returns the slot that belongs to the status item window with the
    /// given frame. Slots and windows share the x axis.
    static func slot(forWindowFrame windowFrame: CGRect, in ownSlots: [CGRect]) -> CGRect? {
        ownSlots.first { slot in
            abs(slot.minX - windowFrame.minX) <= 2 && abs(slot.width - windowFrame.width) <= 2
        }
    }

    /// Returns whether a dropped divider may be reset again after
    /// `resetCount` resets in a row.
    static func shouldReset(resetCount: Int) -> Bool {
        resetCount < maxResets
    }
}
```

- [ ] **Step 4: Run the tests to confirm they pass**

Run: `Scripts/run-tests.sh`
Expected: `PASS HostedHidingWidth` alongside the existing `PASS` lines, exit status 0.

- [ ] **Step 5: Lint**

Run: `swiftlint --strict`
Expected: no violations.

- [ ] **Step 6: Commit**

```bash
git add LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift Scripts/Tests/HostedHidingWidth/main.swift Scripts/run-tests.sh
git commit -m "Add the macOS 27 hiding width calculation

Ported from IceMelt (pnikolaidis/icemelt, PR #46), GPL-3.0."
```

---

### Task 2: Read `MenuBarAgent`'s layout

**Files:**
- Modify: `Shared/Utilities/AXHelpers.swift` (add three helpers)
- Create: `LynxBar/MenuBar/ControlItem/MenuBarAgentLayout.swift`

**Interfaces:**
- Produces:
  - `AXHelpers.windows(for app: Application) -> [UIElement]`
  - `AXHelpers.description(for element: UIElement) -> String?`
  - `AXHelpers.pid(for element: UIElement) -> pid_t?`
  - `@available(macOS 27.0, *) struct MenuBarAgentLayout { var ownSlots: [CGRect]; var otherSlots: [CGRect]; var chevron: CGRect?; static func current() -> MenuBarAgentLayout? }`

This reads live Accessibility state, so there's no script test. It's checked by hand in Step 3 and by Task 4's manual checks.

- [ ] **Step 1: Add the AX helpers**

In `Shared/Utilities/AXHelpers.swift`, add inside `enum AXHelpers` after `role(for:)`:

```swift
    static func windows(for app: Application) -> [UIElement] {
        queue.sync { try? app.windows() } ?? []
    }

    static func description(for element: UIElement) -> String? {
        queue.sync { try? element.attribute(.description) }
    }

    static func pid(for element: UIElement) -> pid_t? {
        queue.sync { try? element.pid() }
    }
```

- [ ] **Step 2: Create the layout reader**

Create `LynxBar/MenuBar/ControlItem/MenuBarAgentLayout.swift`:

```swift
//
//  MenuBarAgentLayout.swift
//  LynxBar
//

import AXSwift
import Cocoa

/// The status item layout of `MenuBarAgent`, which hosts the menu bar's
/// status items on macOS 27.
///
/// The agent's Accessibility window has one slot per item. A slot's child
/// element belongs to the process that created the item, which is how Lynx
/// Bar finds its own control items. An item the system dropped (for example,
/// a divider that is too wide) has no slot.
@available(macOS 27.0, *)
struct MenuBarAgentLayout {
    /// The bundle identifier of the process that hosts the menu bar.
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    /// The Accessibility description of the system's overflow button.
    static let chevronDescription = "Show Hidden Menu Bar Items"

    /// Frames of the slots that belong to Lynx Bar's own status items.
    var ownSlots = [CGRect]()

    /// Frames of every other item's slot.
    var otherSlots = [CGRect]()

    /// The frame of the overflow button, if it's shown.
    var chevron: CGRect?

    /// Reads the current layout, or returns `nil` if the agent can't be read.
    static func current() -> MenuBarAgentLayout? {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleIdentifier).first,
            let app = AXHelpers.application(for: agent)
        else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var layout = MenuBarAgentLayout()
        for window in AXHelpers.windows(for: app) {
            for slot in AXHelpers.children(for: window) {
                guard let frame = AXHelpers.frame(for: slot) else {
                    continue
                }
                let element = AXHelpers.children(for: slot).first ?? slot
                if AXHelpers.description(for: element) == chevronDescription {
                    layout.chevron = frame
                } else if AXHelpers.pid(for: element) == ownPID {
                    layout.ownSlots.append(frame)
                } else {
                    layout.otherSlots.append(frame)
                }
            }
        }
        return layout
    }
}
```

- [ ] **Step 3: Build and lint**

Run: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build 2>&1 | tail -3` and `swiftlint --strict`
Expected: `** BUILD SUCCEEDED **`, no lint violations. If `app.windows()` doesn't compile because AXSwift's signature differs, use `try? app.arrayAttribute(.windows)` instead, which returns `[UIElement]?`.

- [ ] **Step 4: Commit**

```bash
git add Shared/Utilities/AXHelpers.swift LynxBar/MenuBar/ControlItem/MenuBarAgentLayout.swift
git commit -m "Read MenuBarAgent's status item layout on macOS 27"
```

---

### Task 3: Turn off item-list features on macOS 27

**Files:**
- Modify: `LynxBar/MenuBar/MenuBarItems/MenuBarItemManager.swift:17-31, 359`
- Modify: `LynxBar/Main/AppState.swift:65-69`
- Modify: `LynxBar/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift:54-55`
- Modify: `LynxBar/MenuBar/Search/MenuBarSearchPanel.swift:253-254`
- Modify: `LynxBar/MenuBar/LynxShelf/LynxShelf.swift:364-365`
- Modify: `LynxBar/Settings/Models/GeneralSettings.swift` (add `isLynxShelfActive`)
- Modify: `LynxBar/MenuBar/MenuBarSection.swift:58-60`
- Modify: `LynxBar/MenuBar/MenuBarManager.swift:165`
- Modify: `LynxBar/Events/HIDEventManager.swift:385`
- Modify: `LynxBar/Settings/SettingsPanes/GeneralSettingsPane.swift:184-187`

**Interfaces:**
- Produces:
  - `MenuBarItemManager.itemsUnavailableMessage: String?` (`@Published private(set)`), replacing `helperFailureReason`
  - `MenuBarItemManager.setItemsUnavailable(message: String, reason: String)`, replacing `setHelperFailure(_:)`
  - `MenuBarItemManager.unsupportedOnMacOS27Message: String` (static)
  - `GeneralSettings.isLynxShelfActive: Bool`

- [ ] **Step 1: Replace the helper failure state in `MenuBarItemManager`**

Replace lines 17–31 (from `/// Why the \`MenuBarItemService\` helper can't be used` through the end of `setHelperFailure`) with:

```swift
    /// Why menu bar items can't be listed, as a message for the user, or
    /// `nil` if they can.
    ///
    /// While this is set, items are neither cached nor moved. It's set when
    /// the `MenuBarItemService` helper can't be used (items can't be told
    /// apart without it on macOS 26), and always on macOS 27, where items
    /// aren't listed yet.
    @Published private(set) var itemsUnavailableMessage: String?

    /// The message shown when the helper couldn't start.
    static let helperUnavailableMessage = "Lynx Bar's helper couldn't start. Build Lynx Bar with a signing certificate (see README)."

    /// The message shown on macOS 27, where items aren't listed yet.
    static let unsupportedOnMacOS27Message = "Showing menu bar items isn't supported on macOS 27 yet."

    /// Records that menu bar items can't be listed.
    func setItemsUnavailable(message: String, reason: String) {
        logger.error("Menu bar items unavailable: \(reason, privacy: .public)")
        itemsUnavailableMessage = message
        itemCache = ItemCache(displayID: nil)
    }
```

In `cacheItemsRegardless`, replace:

```swift
        guard helperFailureReason == nil else {
            logger.debug("Skipping menu bar item cache: helper unavailable")
```

with:

```swift
        guard itemsUnavailableMessage == nil else {
            logger.debug("Skipping menu bar item cache: items unavailable")
```

- [ ] **Step 2: Gate the helper in `AppState`**

Replace:

```swift
        if #available(macOS 26.0, *) {
            if let failure = await MenuBarItemService.Connection.shared.start() {
                itemManager.setHelperFailure(failure)
            }
        }
```

with:

```swift
        if #available(macOS 27.0, *) {
            // macOS 27 hosts every item in MenuBarAgent, so the helper's
            // window-to-app mapping has nothing to work on yet.
            itemManager.setItemsUnavailable(
                message: MenuBarItemManager.unsupportedOnMacOS27Message,
                reason: "macOS 27 hosts menu bar items in MenuBarAgent"
            )
        } else if #available(macOS 26.0, *) {
            if let failure = await MenuBarItemService.Connection.shared.start() {
                itemManager.setItemsUnavailable(
                    message: MenuBarItemManager.helperUnavailableMessage,
                    reason: failure
                )
            }
        }
```

- [ ] **Step 3: Show the message in the three views**

`MenuBarLayoutSettingsPane.swift`, replace:

```swift
            if itemManager.helperFailureReason != nil {
                Text(MenuBarItemManager.helperUnavailableMessage)
```

with:

```swift
            if let message = itemManager.itemsUnavailableMessage {
                Text(message)
```

`MenuBarSearchPanel.swift`, replace:

```swift
        if itemManager.helperFailureReason != nil {
            Text(MenuBarItemManager.helperUnavailableMessage)
```

with:

```swift
        if let message = itemManager.itemsUnavailableMessage {
            Text(message)
```

`LynxShelf.swift`, replace:

```swift
        } else if itemManager.helperFailureReason != nil {
            Text(MenuBarItemManager.helperUnavailableMessage)
```

with:

```swift
        } else if let message = itemManager.itemsUnavailableMessage {
            Text(message)
```

- [ ] **Step 4: Treat the Shelf as off on 27**

In `GeneralSettings.swift`, add directly below `@Published var useLynxShelf = false`:

```swift

    /// A Boolean value that indicates whether the Lynx Shelf is in use.
    ///
    /// Always `false` on macOS 27, where menu bar items can't be listed yet.
    /// The stored setting is kept, so the Shelf comes back once they can.
    var isLynxShelfActive: Bool {
        if #available(macOS 27.0, *) {
            return false
        }
        return useLynxShelf
    }
```

In `MenuBarSection.swift`, replace:

```swift
        appState?.settings.general.useLynxShelf ?? false
```

with:

```swift
        appState?.settings.general.isLynxShelfActive ?? false
```

In `MenuBarManager.swift:165`, replace `!appState.settings.general.useLynxShelf,` with `!appState.settings.general.isLynxShelfActive,`.

In `HIDEventManager.swift:385`, replace `!appState.settings.general.useLynxShelf` with `!appState.settings.general.isLynxShelfActive`.

In `GeneralSettingsPane.swift`, replace the `useLynxShelf` view:

```swift
    @ViewBuilder
    private var useLynxShelf: some View {
        Toggle("Use Lynx Shelf", isOn: $settings.useLynxShelf)
            .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
    }
```

with:

```swift
    @ViewBuilder
    private var useLynxShelf: some View {
        if #available(macOS 27.0, *) {
            Toggle("Use Lynx Shelf", isOn: $settings.useLynxShelf)
                .disabled(true)
                .annotation(LocalizedStringKey(MenuBarItemManager.unsupportedOnMacOS27Message))
        } else {
            Toggle("Use Lynx Shelf", isOn: $settings.useLynxShelf)
                .annotation("Show hidden menu bar items in a separate bar below the menu bar.")
        }
    }
```

- [ ] **Step 5: Confirm no old names remain**

Run: `grep -rn "helperFailureReason\|setHelperFailure" LynxBar Shared`
Expected: no output.

- [ ] **Step 6: Build, lint, test**

Run: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build 2>&1 | tail -3 && swiftlint --strict && Scripts/run-tests.sh`
Expected: `** BUILD SUCCEEDED **`, no violations, all `PASS`.

- [ ] **Step 7: Commit**

```bash
git add -A LynxBar
git commit -m "Say item lists aren't supported on macOS 27 instead of loading forever

On macOS 27 the helper isn't started, item caching is skipped, and the
Lynx Shelf counts as off without changing the stored setting."
```

---

### Task 4: Measure and apply hiding widths on macOS 27

**Files:**
- Modify: `LynxBar/MenuBar/MenuBarItems/MenuBarItemManager.swift` (published state, triggers in `configureCancellables`)
- Create: `LynxBar/MenuBar/MenuBarItems/MenuBarItemManager+HostedHiding.swift`
- Modify: `LynxBar/MenuBar/ControlItem/ControlItem.swift` (`Lengths`, new state, subscriptions, `updateStatusItemVisibility`)
- Modify: `LynxBar/MenuBar/MenuBarSection.swift` (`show()`, `hide()`)

**Interfaces:**
- Consumes: everything in `HostedHidingWidth` (Task 1), `MenuBarAgentLayout.current()` (Task 2), `ControlItem.frame`, `ControlItem.state`, `MenuBarManager.section(withName:)`, `NSScreen.screenWithActiveMenuBar`, `NSScreen.getApplicationMenuFrame()`, `NSScreen.frameOfNotch`, `NSScreen.displayID`
- Produces:
  - `MenuBarItemManager.hostedHidingWidths: [ControlItem.Identifier: CGFloat]` (`@Published private(set)`)
  - `MenuBarItemManager.hostedDividersToReset: Set<ControlItem.Identifier>` (`@Published private(set)`)
  - `MenuBarItemManager.requestHostedMeasurement(after delay: Duration = .zero)`
  - `MenuBarItemManager.updateHostedHidingWidths()` (`@available(macOS 27.0, *)`)

- [ ] **Step 1: Add the published state and trigger subject to `MenuBarItemManager`**

Below `@Published private(set) var itemsUnavailableMessage: String?` and its two static messages, add:

```swift

    /// How wide each section divider should be to hide its section on
    /// macOS 27, keyed by the divider's identifier. A divider that hasn't
    /// been measured yet is absent. See `updateHostedHidingWidths()`.
    @Published private(set) var hostedHidingWidths = [ControlItem.Identifier: CGFloat]()

    /// Dividers that the system dropped from the bar on macOS 27. They take
    /// their standard length until a measurement finds them in the bar again.
    @Published private(set) var hostedDividersToReset = Set<ControlItem.Identifier>()

    /// Resets in a row per divider, to stop a reflow loop.
    var hostedResetCounts = [ControlItem.Identifier: Int]()

    /// Requests a hiding-width measurement on macOS 27.
    let hostedMeasurementRequests = PassthroughSubject<Void, Never>()
```

Add these two setters right below (the extension in Step 2 can't write `private(set)` properties):

```swift

    /// Updates ``hostedHidingWidths``.
    func setHostedHidingWidths(_ widths: [ControlItem.Identifier: CGFloat]) {
        if widths != hostedHidingWidths {
            hostedHidingWidths = widths
        }
    }

    /// Updates ``hostedDividersToReset``.
    func setHostedDividersToReset(_ identifiers: Set<ControlItem.Identifier>) {
        if identifiers != hostedDividersToReset {
            hostedDividersToReset = identifiers
        }
    }
```

In `configureCancellables(with:)`, directly after `var c = Set<AnyCancellable>()`, add:

```swift

        if #available(macOS 27.0, *) {
            // The room for hiding depends on the frontmost app's menu and on
            // the screen layout (see `updateHostedHidingWidths()`).
            hostedMeasurementRequests
                .merge(with: NSWorkspace.shared.notificationCenter
                    .publisher(for: NSWorkspace.didActivateApplicationNotification)
                    .map { _ in })
                .merge(with: NotificationCenter.default
                    .publisher(for: NSApplication.didChangeScreenParametersNotification)
                    .map { _ in })
                .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
                .sink { [weak self] in
                    self?.updateHostedHidingWidths()
                }
                .store(in: &c)
        }
```

At the end of `performSetup(with:)` (after `configureCancellables(with: appState)`), add:

```swift
        requestHostedMeasurement()
```

- [ ] **Step 2: Create the measurement extension**

Create `LynxBar/MenuBar/MenuBarItems/MenuBarItemManager+HostedHiding.swift`:

```swift
//
//  MenuBarItemManager+HostedHiding.swift
//  LynxBar
//

import Cocoa

// MARK: - Hosted Hiding (macOS 27)

extension MenuBarItemManager {
    /// Requests a hiding-width measurement after the given delay. Does
    /// nothing before macOS 27.
    func requestHostedMeasurement(after delay: Duration = .zero) {
        guard #available(macOS 27.0, *) else {
            return
        }
        Task { @MainActor [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            self?.hostedMeasurementRequests.send()
        }
    }

    /// Measures how wide each section divider should be to hide its section,
    /// and recovers dividers the system dropped from the bar.
    ///
    /// Ported from IceMelt (https://github.com/pnikolaidis/icemelt, PR #46),
    /// GPL-3.0. See ``HostedHidingWidth`` for the rules.
    @available(macOS 27.0, *)
    func updateHostedHidingWidths() {
        guard
            let menuBarManager = appState?.menuBarManager,
            let layout = MenuBarAgentLayout.current(),
            let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        else {
            return
        }

        let regionLeft = hostedRegionLeft(on: screen)
        var widths = hostedHidingWidths
        var toReset = hostedDividersToReset

        for identifier in [ControlItem.Identifier.hidden, .alwaysHidden] {
            guard
                let section = menuBarManager.section(withName: identifier == .hidden ? .hidden : .alwaysHidden),
                section.isEnabled,
                let windowFrame = section.controlItem.frame
            else {
                continue
            }

            let slot = HostedHidingWidth.slot(forWindowFrame: windowFrame, in: layout.ownSlots)

            if slot == nil, section.controlItem.state == .hideSection {
                // Dropped by the system (too wide, or stretched before it had
                // a place). Take the standard length so it returns, then
                // measure again. Counts every miss, including one right after
                // a reset, so a divider that never returns can't loop.
                let count = hostedResetCounts[identifier, default: 0]
                guard HostedHidingWidth.shouldReset(resetCount: count) else {
                    if count == HostedHidingWidth.maxResets {
                        logger.error("Divider \(identifier.rawValue, privacy: .public) keeps dropping out of the menu bar; giving up")
                        hostedResetCounts[identifier] = count + 1 // Log once.
                    }
                    continue
                }
                logger.info("Divider \(identifier.rawValue, privacy: .public) isn't in the menu bar; resetting it")
                hostedResetCounts[identifier] = count + 1
                toReset.insert(identifier)
                requestHostedMeasurement(after: .milliseconds(600))
                continue
            }

            if slot != nil, section.controlItem.state == .hideSection {
                if toReset.remove(identifier) == nil {
                    // In the bar at its hiding length, so any loop is over.
                    hostedResetCounts[identifier] = 0
                }
            }

            guard let visibleFrom = HostedHidingWidth.visibleFrom(
                dividerSlot: slot,
                otherSlots: layout.otherSlots,
                chevron: layout.chevron
            ) else {
                continue
            }
            let width = HostedHidingWidth.width(visibleFrom: visibleFrom, regionLeft: regionLeft)
            if HostedHidingWidth.shouldApply(old: widths[identifier], new: width) {
                widths[identifier] = width
            }
        }

        setHostedHidingWidths(widths)
        setHostedDividersToReset(toReset)
    }

    /// Returns where the agent's item area begins on the given screen.
    @available(macOS 27.0, *)
    private func hostedRegionLeft(on screen: NSScreen) -> CGFloat {
        guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
            // A cautious guess that may hide fewer items.
            return HostedHidingWidth.regionLeft(applicationMenuMaxX: screen.frame.midX, notchMaxX: nil)
        }
        // The application menu is reported on the main display, but it's
        // the same width on every display.
        let displayBounds = CGDisplayBounds(screen.displayID)
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let applicationMenuMaxX = displayBounds.minX + (applicationMenuFrame.maxX - mainDisplayBounds.minX)
        return HostedHidingWidth.regionLeft(
            applicationMenuMaxX: applicationMenuMaxX,
            notchMaxX: screen.frameOfNotch?.maxX
        )
    }
}
```

`logger` is `private nonisolated let logger` in `MenuBarItemManager.swift`, so the extension can't see it. Change its declaration there to `nonisolated let logger = Logger.menuBarItemManager` (drop `private`). `hostedResetCounts` is already declared without `private` in Step 1 for the same reason.

- [ ] **Step 3: Apply the width in `ControlItem`**

Add these properties below `private var cancellables = Set<AnyCancellable>()`:

```swift

    /// The width that hides this divider's section on macOS 27, as last
    /// measured by the item manager (see `MenuBarItemManager.hostedHidingWidths`).
    private var hostedHidingWidth: CGFloat?

    /// Whether this divider must take its standard length so that it can
    /// return to the bar on macOS 27.
    private var needsHostedReset = false
```

At the end of the `if let appState { … }` block in `configureCancellables()` (just before its closing brace), add:

```swift

            if isSectionDivider, #available(macOS 27.0, *) {
                appState.itemManager.$hostedHidingWidths
                    .map { [identifier] widths in widths[identifier] }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] width in
                        self?.hostedHidingWidth = width
                        self?.updateStatusItem()
                    }
                    .store(in: &c)

                appState.itemManager.$hostedDividersToReset
                    .map { [identifier] identifiers in identifiers.contains(identifier) }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak self] needsReset in
                        self?.needsHostedReset = needsReset
                        self?.updateStatusItem()
                    }
                    .store(in: &c)
            }
```

Add this method directly above `private func updateStatusItemVisibility(_ isVisible: Bool)`:

```swift
    /// Returns the length for the status item in its current state.
    ///
    /// On macOS 27 a divider hides its section by filling the measured room
    /// (see ``HostedHidingWidth``) instead of using `Lengths.expanded`.
    private func currentLength() -> CGFloat {
        if #available(macOS 27.0, *), isSectionDivider, state == .hideSection {
            if needsHostedReset {
                return Lengths.standard
            }
            let screenWidth = (NSScreen.screenWithActiveMenuBar ?? NSScreen.main)?.frame.width ?? 1_000
            return HostedHidingWidth.length(width: hostedHidingWidth, screenWidth: screenWidth)
        }
        return identifier.length(for: state)
    }
```

In `updateStatusItemVisibility(_:)`, replace `statusItem.length = identifier.length(for: state)` with `statusItem.length = currentLength()`.

- [ ] **Step 4: Re-measure after a section shows or hides**

In `MenuBarSection.swift`, at the end of `show()` (after the final `startRehideChecks()`) and at the end of `hide()` (after `stopRehideChecks()`), add:

```swift
        appState?.itemManager.requestHostedMeasurement(after: .milliseconds(600))
```

`show()` also returns early in its Shelf branch. That branch can't run on 27 (Task 3 makes `useLynxShelf` false there), so it needs no call.

- [ ] **Step 5: Build, lint, test**

Run: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build 2>&1 | tail -3 && swiftlint --strict && Scripts/run-tests.sh`
Expected: `** BUILD SUCCEEDED **`, no violations, all `PASS`.

- [ ] **Step 6: Install and run the manual checks on macOS 27**

Quit the running Lynx Bar first (`osascript -e 'quit app "Lynx Bar"'`). Build with the certificate (`Config/Local.xcconfig`, see memory `test-build-signing`), then copy the Debug product to `~/Applications/Lynx Bar.app` and open it. In a second terminal, watch the log:
`/usr/bin/log stream --predicate 'subsystem == "com.ikentrock.LynxBar"' --info --debug`

Check each, writing down pass or fail:
1. The divider recovers from the `y=1084` state on launch ("resetting it" logged at most once). The hidden items disappear and are listed behind the system `«`.
2. Clicking the Lynx icon shows and hides. So does the hotkey.
3. Auto-rehide fires after the timeout.
4. Always-hidden (⌥-click): hide only it, then both, then show both.
5. While hidden, switch Finder → Mail → Xcode → Finder. Items end up hidden each time. No "giving up" in the log. The bar settles within about 2 s.
6. The Shelf, search (⌘-click menu › Search) and layout pane show "Showing menu bar items isn't supported on macOS 27 yet." The General pane's Shelf toggle is disabled.
7. Set "Section divider style" to "No divider" and show the hidden section. Nothing resets ("resetting it" not logged).

If check 1 or 5 fails because `getApplicationMenuFrame()` returns `nil` on 27 (the log shows the midpoint fallback hiding too little), stop and report. Don't tune the constants blind.

- [ ] **Step 7: Commit**

```bash
git add -A LynxBar
git commit -m "Hide sections on macOS 27 by filling the menu bar's free space

macOS 27 hides items only by moving them into its own overflow, so a divider
now takes the measured room between the app menu and the visible items,
capped at half the display. Dividers the system drops are reset and
re-measured, at most three times in a row.

Ported from IceMelt (pnikolaidis/icemelt, PR #46), GPL-3.0."
```

---

### Task 5: Credit IceMelt and record known limits

**Files:**
- Modify: `README.md` (License section)
- Modify: `FREQUENT_ISSUES.md` (add a macOS 27 entry)

- [ ] **Step 1: Add the credit**

In `README.md`, at the end of the `## License` section, add a paragraph:

```markdown
macOS 27 hiding is ported from [IceMelt](https://github.com/pnikolaidis/icemelt), another
GPL-3.0 fork of Ice.
```

- [ ] **Step 2: Add the known limits**

Read `FREQUENT_ISSUES.md` to match its heading style, then add an entry with this content:

```markdown
## macOS 27: some hidden items stay visible, or the Shelf says it isn't supported

macOS 27 hides menu bar items only by moving them into its own overflow (the `«` button
next to the app menus). Lynx Bar hides a section by filling the free space in the bar, but
macOS drops any item wider than half the screen. When the active app has short menus and
few items are visible, the first hidden items can stay in the bar. Click `«` to see
everything that's hidden.

Lynx Bar can't list menu bar items on macOS 27 yet, so the Lynx Shelf, search and the
Menu Bar Layout pane are turned off there.
```

- [ ] **Step 3: Check and commit**

Run: `Scripts/check-names.sh`
Expected: passes.

```bash
git add README.md FREQUENT_ISSUES.md
git commit -m "Credit IceMelt and document macOS 27 limits"
```
