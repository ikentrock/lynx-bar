# macOS 27 Allowlist Hiding Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On macOS 27, hide the apps the owner ⌘-dragged left of a section divider through MenuBarAgent's private allowlist, and show them by hovering over the Lynx icon.

**Architecture:**
- A pure, script-tested `HostedSections` decides which apps belong to each section and which bundle IDs to allow.
- A thin `HostedAllowlist` wraps the private `MenuBarClientCore` classes through the Objective-C runtime.
- A `@MainActor` `HostedVisibilityManager`, owned by `MenuBarManager`, applies the right allowlist whenever a section shows or hides.
- Everything sits behind `#available(macOS 27.0, *)` and `HostedAllowlist.isAvailable`. Without the facility, behaviour stays exactly as it is today (round B).

**Tech Stack:** Swift 5 / AppKit, AXSwift, Objective-C runtime (`dlopen`, `class_getMethodImplementation`), standalone `swiftc` script tests.

**Spec:** `docs/superpowers/specs/2026-11-10-macos27-allowlist-hiding-design.md`

## Global Constraints

- Every macOS 27 branch is `if #available(macOS 27.0, *)` placed before any macOS 26 branch. Nothing changes on macOS 14–26.
- `HostedHidingWidth.isEnabled` stays `false`; dividers keep their standard length.
- System items are always `0...255`.
- Lynx Bar's own bundle ID is always allowed and never in a hidden set.
- Apple-owned items (bundle ID starting `com.apple.`) are never in a hidden set.
- The facility is used only when Lynx Bar runs directly from `/Applications`. Otherwise the General settings note reads exactly: "Move Lynx Bar to the Applications folder to hide items on macOS 27."
- New stored keys use Lynx names: `HostedHiddenApps`, `HostedAlwaysHiddenApps`. Never rename existing keys.
- Lint: `swiftlint --strict` must pass. Every file needs the header `//\n//  <FileName>.swift\n//  LynxBar\n//`, 4-space indentation, trailing commas in multiline collections, and no force unwraps.
- Build: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug build`. Tests: `Scripts/run-tests.sh`.
- Install for manual checks: quit Lynx Bar, `ditto` the Debug product to `/Applications/Lynx Bar.app`, `open` it. It's signed with the "Luisen" certificate, so permission grants survive.

## Review Focus

1. **An app that has quit while hidden** (quit, then relaunched). It must stay hidden after relaunch. Covered by a test in Task 1: an unseen app keeps its membership.
2. **An app with icons on both sides of a divider** (a system monitor with several icons). It must land in the leftmost section, never split. Covered by a test in Task 1.
3. **The Lynx icon dragged left of the hidden divider.** It must never be hidden. Covered by a test in Task 1: own items are ignored, and the own bundle ID is always in the allowlist.
4. **Quit or crash while hidden.** Everything must come back. Covered by Task 4's manual check, using `kill -9`.
5. **Moving the pointer down into a just-opened menu of a revealed app.** It must not rehide and close that menu. Covered by Task 5's manual check.

---

### Task 1: `HostedSections` decision logic

**Files:**
- Create: `LynxBar/MenuBar/ControlItem/HostedSections.swift`
- Create: `Scripts/Tests/HostedSections/main.swift`
- Modify: `Scripts/run-tests.sh` (add `build HostedSections ../LynxBar/MenuBar/ControlItem/HostedSections.swift` and `run HostedSections` after `HostedOverflow`)

**Interfaces:**
- Produces (Foundation and CoreGraphics only, no AppKit, so it compiles in the script test):

```swift
/// One item in MenuBarAgent's item-list window, left to right.
struct HostedItem: Equatable {
    let bundleIdentifier: String?
    let frame: CGRect
    let isOwn: Bool
}

/// The apps the owner put in each hiding section.
struct HostedSectionSets: Equatable {
    var hidden: Set<String> = []
    var alwaysHidden: Set<String> = []
}

enum HostedSections {
    /// Whether an app may be put in a hidden set.
    static func isHideable(_ bundleIdentifier: String, ownBundleIdentifier: String) -> Bool

    /// Reassigns every hideable app seen in `items` by its leftmost icon.
    /// An app left of the always-hidden divider goes to always-hidden; left
    /// of the hidden divider, to hidden; otherwise to neither. Apps not seen
    /// keep their membership. A nil divider means that section is off.
    static func updatedSets(
        _ stored: HostedSectionSets,
        items: [HostedItem],
        hiddenDivider: CGRect?,
        alwaysHiddenDivider: CGRect?,
        ownBundleIdentifier: String
    ) -> HostedSectionSets

    /// The bundle identifiers to allow: `candidates`, minus the sets of the
    /// hidden sections, plus our own. Sorted, so equal inputs give equal output.
    static func allowlist(
        sets: HostedSectionSets,
        hidesHidden: Bool,
        hidesAlwaysHidden: Bool,
        candidates: Set<String>,
        ownBundleIdentifier: String
    ) -> [String]

    /// The live slot of the Lynx icon: our own slot that matches no divider
    /// window (by `HostedHidingWidth.slot(forWindowFrame:in:)`'s rule: same
    /// width ±2, nearest x).
    static func lynxIconSlot(ownSlots: [CGRect], dividerWindowFrames: [CGRect]) -> CGRect?

    /// Whether the app bundle sits directly in /Applications.
    static func isInApplicationsFolder(_ bundleURL: URL) -> Bool
}
```

- [ ] **Step 1: Write the failing tests** in `Scripts/Tests/HostedSections/main.swift`, with the file header `//\n//  main.swift\n//  Tests\n//`.

Use `own = "com.ikentrock.LynxBar"`. For x-positions, use a helper `item(_ id: String?, _ x: CGFloat, own: Bool = false)` that returns a 30-wide frame at `x`. Dividers are `CGRect(x: 567, y: 0, width: 16, height: 30)` (hidden) and `CGRect(x: 200, ...)` (always-hidden).

```swift
expect(!HostedSections.isHideable("com.apple.controlcenter", ownBundleIdentifier: own), "Apple items are never hideable")
expect(!HostedSections.isHideable(own, ownBundleIdentifier: own), "Lynx Bar is never hideable")
expect(HostedSections.isHideable("com.example.meetings", ownBundleIdentifier: own), "other apps are hideable")

let items = [item("com.example.chat", 100), item("com.example.assistant", 300), item("com.example.meetings", 400),
             item(own, 450, own: true), item("com.example.messenger", 700), item(nil, 750),
             item("com.apple.weather.menu", 320)]
let sets = HostedSections.updatedSets(.init(), items: items, hiddenDivider: hiddenDivider,
                                      alwaysHiddenDivider: nil, ownBundleIdentifier: own)
expect(sets.hidden == ["com.example.chat", "com.example.assistant", "com.example.meetings"], "apps left of the hidden divider are hidden")
expect(sets.alwaysHidden.isEmpty, "no always-hidden divider, no always-hidden apps")

let withAH = HostedSections.updatedSets(.init(), items: items, hiddenDivider: hiddenDivider,
                                        alwaysHiddenDivider: alwaysHiddenDivider, ownBundleIdentifier: own)
expect(withAH.alwaysHidden == ["com.example.chat"] && !withAH.hidden.contains("com.example.chat"), "left of the always-hidden divider is always-hidden only")

let split = HostedSections.updatedSets(.init(), items: [item("com.example.monitor", 500), item("com.example.monitor", 900)],
                                       hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own)
expect(split.hidden == ["com.example.monitor"], "an app with icons on both sides goes to the leftmost section")

let kept = HostedSections.updatedSets(.init(hidden: ["com.example.meetings"]), items: [item("com.example.messenger", 700)],
                                      hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own)
expect(kept.hidden == ["com.example.meetings"], "an app that isn't drawn keeps its membership")

let moved = HostedSections.updatedSets(.init(hidden: ["com.example.meetings"]), items: [item("com.example.meetings", 800)],
                                       hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own)
expect(moved.hidden.isEmpty, "an app seen right of the divider leaves the hidden set")

let candidates: Set = ["com.example.chat", "com.example.meetings", "com.example.messenger", own]
let state = HostedSectionSets(hidden: ["com.example.meetings"], alwaysHidden: ["com.example.chat"])
expect(HostedSections.allowlist(sets: state, hidesHidden: true, hidesAlwaysHidden: true, candidates: candidates, ownBundleIdentifier: own)
       == ["com.example.messenger", "com.ikentrock.LynxBar"], "hiding both sections excludes both sets")
expect(HostedSections.allowlist(sets: state, hidesHidden: false, hidesAlwaysHidden: true, candidates: candidates, ownBundleIdentifier: own)
       == ["com.example.meetings", "com.example.messenger", "com.ikentrock.LynxBar"], "showing hidden keeps always-hidden excluded")
expect(HostedSections.allowlist(sets: .init(hidden: [own]), hidesHidden: true, hidesAlwaysHidden: false, candidates: [], ownBundleIdentifier: own)
       == [own], "our own bundle ID is always allowed")

// Measured on 27.2: Lynx icon 33 pt, hidden divider 16 pt; windows sit 56 pt right of the live slots.
expect(HostedSections.lynxIconSlot(ownSlots: [CGRect(x: 1098, y: 0, width: 33, height: 30), CGRect(x: 1347, y: 0, width: 16, height: 30)],
                                   dividerWindowFrames: [CGRect(x: 1403, y: 1050, width: 16, height: 30)])
       == CGRect(x: 1098, y: 0, width: 33, height: 30), "the Lynx icon is the own slot that matches no divider")

expect(HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Lynx Bar.app")), "/Applications counts")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Applications/Lynx Bar.app")), "~/Applications doesn't")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tools/Lynx Bar.app")), "a subfolder doesn't")

finishTests("HostedSections")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `Scripts/run-tests.sh`
Expected: the HostedSections build fails with "cannot find 'HostedSections' in scope".

- [ ] **Step 3: Implement `HostedSections.swift`.** "Left of" means `item.frame.maxX <= divider.minX + 2`. For `lynxIconSlot`, reuse `HostedHidingWidth.slot(forWindowFrame:in:)`: compile `HostedHidingWidth.swift` into the test as well, so the test's build line in `run-tests.sh` lists both files.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `Scripts/run-tests.sh && swiftlint --strict`
Expected: `PASS HostedSections` along with every other test, and 0 lint violations.

- [ ] **Step 5: Commit** — `git add LynxBar/MenuBar/ControlItem/HostedSections.swift Scripts/Tests/HostedSections Scripts/run-tests.sh && git commit -m "Decide macOS 27 hidden apps and allowlists in a tested helper"`

### Task 2: Read the item-list window

**Files:**
- Modify: `LynxBar/MenuBar/ControlItem/MenuBarAgentLayout.swift`

**Interfaces:**
- Consumes: `HostedItem` (Task 1).
- Produces: `MenuBarAgentLayout.listItems: [HostedItem]`, left to right, sorted by `frame.minX`. They come from the agent window that is *not* the live one. With no identified `«`, they come from the first window. Bundle IDs come from `NSRunningApplication(processIdentifier:)?.bundleIdentifier`. `isOwn` means the PID is our own.

- [ ] **Step 1: Implement.** Extend `current()`: it already reads every window's slots into `windows`. Build `listItems` from `windows[listIndex]`, where `listIndex` is the first index ≠ `liveIndex`, or `0` when `liveIndex` is `nil`. Only `.item` slots count. Don't change how `ownSlots`, `otherSlots` or `chevron` are read.

- [ ] **Step 2: Verify**

Run: `xcodebuild … build`, install, then add a temporary `logger.debug` of `listItems.map(\.bundleIdentifier)` in `updateHostedHidingWidths` and read it with `log stream`. Remove the log line before committing.
Expected: the debug line lists every app with an icon, in bar order, including the hidden ones.

- [ ] **Step 3: Commit** — `git commit -am "Read MenuBarAgent's item-list window on macOS 27"`

### Task 3: `HostedAllowlist` runtime wrapper

**Files:**
- Create: `LynxBar/MenuBar/ControlItem/HostedAllowlist.swift`

**Interfaces:**
- Consumes: `HostedSections.isInApplicationsFolder` (Task 1).
- Produces:

```swift
@available(macOS 27.0, *)
@MainActor
final class HostedAllowlist {
    /// Why the facility can't be used, or nil if it can. Checked once:
    /// the framework loads, both classes and all four selectors exist,
    /// and Bundle.main.bundleURL is in /Applications.
    static let unavailableReason: String?
    static var isAvailable: Bool { unavailableReason == nil }

    /// Activates an assertion allowing `bundleIdentifiers` and system items
    /// 0...255, then invalidates the previous one (in that order: the new
    /// one applies once the old is gone, with no flash).
    func apply(allowing bundleIdentifiers: [String]) async throws

    /// Invalidates the active assertion, if any. Everything is drawn again.
    func clear()
}
```

- [ ] **Step 1: Implement.** Follow the spec's "The facility" section:
  - `dlopen` the framework at `/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore`.
  - Get both classes with `NSClassFromString`, then `alloc` and the designated initializers through `class_getMethodImplementation` and `@convention(c)` function types. Never call `init()` from Swift; it traps.
  - Store the completion block in a `let` of type `@convention(block) (NSError?) -> Void` before passing it, so it can escape.
  - Bridge the completion to `async throws`. Activation counts as failed when the error is non-nil, or when no completion arrives within 2 s.
  - Reasons, verbatim:
    - "Move Lynx Bar to the Applications folder to hide items on macOS 27." when not in `/Applications`.
    - "This version of macOS doesn't support hiding items." when the framework, a class or a selector is missing.
  - Log at debug on every apply and clear, with the count; log errors at error.

- [ ] **Step 2: Verify**

Run: `xcodebuild … build && swiftlint --strict`
Expected: BUILD SUCCEEDED, 0 violations. Behaviour is checked in Task 4.

- [ ] **Step 3: Commit** — `git add LynxBar/MenuBar/ControlItem/HostedAllowlist.swift && git commit -m "Wrap MenuBarAgent's allowlist assertion on macOS 27"`

### Task 4: Hide and show sections through the allowlist

**Files:**
- Create: `LynxBar/MenuBar/HostedVisibilityManager.swift`
- Modify: `LynxBar/Utilities/Defaults.swift` (add `case hostedHiddenApps = "HostedHiddenApps"` and `case hostedAlwaysHiddenApps = "HostedAlwaysHiddenApps"`)
- Modify: `LynxBar/MenuBar/MenuBarManager.swift` (own and set up the manager)
- Modify: `LynxBar/MenuBar/MenuBarSection.swift` (`show()` and `hideInMenuBar()` notify it)
- Modify: `LynxBar/Main/AppDelegate.swift` (add `applicationWillTerminate(_:)` that calls `clear()`)

**Interfaces:**
- Consumes:
  - `HostedSections.updatedSets`, `HostedSections.allowlist` (Task 1)
  - `MenuBarAgentLayout.listItems` (Task 2)
  - `HostedAllowlist.apply(allowing:)`, `clear()`, `isAvailable` (Task 3)
- Produces:

```swift
@available(macOS 27.0, *)
@MainActor
final class HostedVisibilityManager {
    init(appState: AppState)
    /// Reads the bar (when a section is about to hide), updates and stores
    /// the sets, and applies the allowlist for the sections' current states.
    /// Calls are serialized: each waits for the one before it.
    func sectionsDidChange()
    /// Re-applies the current allowlist (after wake).
    func reapply()
    func clear()
}
```

`MenuBarManager` gets `private(set) var hostedVisibility: AnyObject?`. Store it as `AnyObject` because of availability, and cast it at the call sites inside `#available`. It's created in `performSetup` when `HostedAllowlist.isAvailable`.

- [ ] **Step 1: Implement the manager.**
  - **Sets.** Load them from the two Defaults keys (string arrays) at init. If neither key is present, compute them once from the current `listItems`.
  - **Reading the bar.** `sectionsDidChange()` re-reads the bar only when a section goes from shown to hidden; everything is drawn at that moment. It passes `updatedSets` the divider window frames matched to list slots: `controlItem.frame` for each divider, matched to a `listItems` own frame with `HostedHidingWidth.slot(forWindowFrame:in:)`. A section that is disabled gets `nil`.
  - **Allowlist candidates.** The union of the `listItems` bundle IDs and the bundle IDs of `NSWorkspace.shared.runningApplications` whose `activationPolicy != .prohibited`.
  - **Applying.** When no section is hidden, `clear()`; otherwise `apply(allowing:)`. If `apply` throws, log the error, `clear()`, and stop using the manager for the session. Set `MenuBarManager.hostedVisibility = nil`, and `HostedAllowlist`'s availability falls back to round-B behaviour.
  - **Wake.** Observe `NSWorkspace.didWakeNotification` and call `reapply()`.
  - **New apps.** Observe `NSWorkspace.didLaunchApplicationNotification` and call `reapply()`. The allowlist names the apps to keep, so an app launched while a section is hidden would otherwise vanish. The spec says it shows until the next hide.

- [ ] **Step 2: Wire it in.**
  - `MenuBarSection.show()` and `hideInMenuBar()` call `sectionsDidChange()` after setting the control item states, inside `if #available(macOS 27.0, *)`.
  - `AppDelegate.applicationWillTerminate` calls `clear()`.

- [ ] **Step 3: Verify by hand** (install to `/Applications`, then stream logs with `/usr/bin/log stream --level debug --predicate 'subsystem == "com.ikentrock.LynxBar"'`):
  - ⌘-drag two apps left of the "|" divider, then click the Lynx icon twice. Expected: after the second click both icons are gone, and the log shows an apply that excludes 2 apps.
  - Click the Lynx icon. Expected: both are back in their places, and the log shows a clear.
  - Hide, then quit from the Lynx menu. Expected: everything is back.
  - Hide, then `kill -9 $(pgrep -x "Lynx Bar")`. Expected: everything is back.
  - Relaunch. Expected: the same apps hide on the first hide.
  - Quit one of them while hidden and relaunch it. Expected: it stays hidden.
  - Launch an app with a menu bar icon that isn't in a set (quit it first) while hidden. Expected: its icon shows.
  - `Scripts/run-tests.sh && swiftlint --strict` pass.

- [ ] **Step 4: Commit** — `git add -A && git commit -m "Hide sections through MenuBarAgent's allowlist on macOS 27"`

### Task 5: Show on hover over the Lynx icon

**Files:**
- Modify: `LynxBar/Settings/Models/GeneralSettings.swift` (`isShowOnHoverActive`)
- Modify: `LynxBar/Events/HIDEventManager.swift` (`handleShowOnHover`, a new `isMouseInsideHostedLynxIcon`, a new `isMenuOpen`)
- Modify: `LynxBar/MenuBar/MenuBarSection.swift` (timed rehide defers while a menu is open)
- Modify: `LynxBar/Settings/SettingsPanes/GeneralSettingsPane.swift`, `AdvancedSettingsPane.swift`

**Interfaces:**
- Consumes:
  - `HostedSections.lynxIconSlot` (Task 1)
  - `MenuBarAgentLayout.current()?.ownSlots`
  - `HostedAllowlist.isAvailable`, `unavailableReason` (Task 3)
- Produces:
  - `HIDEventManager.isMouseInsideHostedLynxIcon(appState:) -> Bool` (macOS 27)
  - `HIDEventManager.isMenuOpen: Bool`: true when an on-screen window at `CGWindowLevelForKey(.popUpMenuWindow)` exists.

- [ ] **Step 1: Implement.**
  - `isShowOnHoverActive`: on macOS 27, return `showOnHover && HostedAllowlist.isAvailable`.
  - In `handleShowOnHover`, on macOS 27:
    - **Show** when the pointer is inside the hosted Lynx icon slot (not empty space), after the existing delay, re-checked after the delay.
    - **Hide** as today, but skip while `isMenuOpen`.
  - The timed rehide in `MenuBarSection.startRehideChecks` restarts its checks instead of hiding while `isMenuOpen`.
  - **Settings, on macOS 27:**
    - Show the normal "Show on hover" toggle when `HostedAllowlist.isAvailable`, with the annotation "Hover over the Lynx icon to show hidden menu bar items." Otherwise keep the disabled toggle, and show `HostedAllowlist.unavailableReason` as a note under it.
    - Show the hover-delay slider in Advanced when available.

- [ ] **Step 2: Verify by hand:**
  - Hover the Lynx icon. Expected: hidden apps appear after the delay.
  - Click a revealed app and move down into its menu. Expected: the menu stays open, and nothing rehides.
  - Close the menu and move away. Expected: rehides.
  - Hover over empty bar space. Expected: nothing happens.
  - Record 20 s of hovering around the Lynx icon with the stream. Expected: no show/hide loop (at most one show per entry).
  - `Scripts/run-tests.sh && swiftlint --strict` pass.

- [ ] **Step 3: Commit** — `git commit -am "Show hidden apps on hover over the Lynx icon on macOS 27"`

### Task 6: Docs and full check

**Files:**
- Modify: `FREQUENT_ISSUES.md` (rewrite the macOS 27 section)
- Modify: `CLAUDE.md` (macOS 27 paragraph)

- [ ] **Step 1: Write the docs.**
  - **`FREQUENT_ISSUES.md`.** The macOS 27 section covers:
    - hiding works per app
    - Lynx Bar must be in `/Applications`
    - Now Playing and Focus hide while a section is hidden
    - apps outside `/Applications` or without a bundle ID may stay hidden
    - don't run another menu bar manager at the same time
    - the fallback when unavailable
  - **`CLAUDE.md`.** Name `HostedSections`, `HostedAllowlist` and `HostedVisibilityManager`, and the private framework.

- [ ] **Step 2: Full check:**
  - `Scripts/run-tests.sh`, `swiftlint --strict`, the Debug build.
  - Every manual check in Tasks 4 and 5 once more on the final build.
  - Copy the app to `~/Applications`, run it from there, and confirm the note shows and round-B behaviour works. Then delete that copy.
  - The always-hidden section on: option-click hides and shows it.
  - Sleep and wake while hidden: still hidden.

- [ ] **Step 3: Commit** — `git commit -am "Document allowlist hiding on macOS 27"`
