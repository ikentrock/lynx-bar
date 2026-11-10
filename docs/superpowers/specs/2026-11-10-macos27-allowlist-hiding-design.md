# macOS 27 support, round C: real hiding with MenuBarAgent's allowlist

Date: 2026-11-10
Status: design, awaiting review

## Why

On macOS 27 Lynx Bar can't hide other apps' icons the way it does on macOS 26
(see `2026-10-13-macos27-hiding-design.md`). Round A stretched the hidden
divider to fill the free space, which left a wide, clickable blank in the bar
and could push the Lynx icon into the system's `«`. Round B (PR #2) switched
that off (`HostedHidingWidth.isEnabled = false`), so today macOS alone decides
what is hidden, by what fits, and the owner can't choose.

The owner's habit from macOS 26: a few work apps (Teams, OneDrive, Rocket.Chat,
Ollama) are kept out of the bar. When one is needed, they **hover over the Lynx
icon**, the hidden icons appear in the bar, they click the one they want, and
the icons get out of the way again. They choose which apps are hidden
themselves, by **⌘-dragging icons past the divider**, as on macOS 26.

A private macOS 27 facility makes this possible again. A spike on 2026-11-10
(macOS 27.2, build 26B123) confirmed it.

## The facility: assessment-mode allowlist

`/System/Library/PrivateFrameworks/MenuBarClientCore.framework` (load with
`dlopen`) contains two Swift classes exposed to Objective-C:

- `MBAssessmentModeConfiguration`
  - `initWithAllowedSystemItems:allowedBundleIdentifiers:`: both arguments
    are `NSArray`. System items are `NSNumber`s; pass `0...255`, because
    `0...63` reportedly breaks Screen Mirroring.
  - `initWithUnrestrictedMenuBarItems`
  - Plain `init()` traps ("unimplemented initializer"). Use `alloc` plus a
    designated initializer through the Objective-C runtime.
- `MBAssessmentModeAssertion`
  - `init` (via `alloc`, then `init`)
  - `activateWithConfiguration:completionHandler:`: the completion is a
    block taking `NSError?`.
  - `invalidate`

While an assertion is active, MenuBarAgent draws only the status items of
the allowlisted bundle identifiers (and the allowed system items). Every
other app's icons vanish from the bar and from both of the agent's
Accessibility windows. The apps keep running. `invalidate`, or the owning
process exiting, restores everything at once.

Spike results (throwaway script, not in the repo):

| Check | Result |
| --- | --- |
| Activation | completion error `nil` |
| Target app's icon (Ollama) | gone within 2 s, the app kept running |
| Other apps and system items | untouched |
| `invalidate` | everything back at once |
| An allowlisted app running from `~/Applications` (Lynx Bar) | hidden anyway |
| The same app running from `/Applications` | stayed visible |
| Order after `invalidate` | every icon back in exactly the same place |
| A second assertion activated while the first is active | no effect until the first is invalidated, then applies with no flash |
| Apple's Now Playing and Focus icons | hidden while any assertion is active, even with system items `0...4095` or their `com.apple.menuextra.*` identifiers allowlisted. Wi-Fi, Control Center and the clock stay. |

Prior art: Hidden Bar 1.11.1 ships this as its "native engine" (`NativeVisibilityEngine`) and runs
on 27.2. Stash (`brentc22/stash`, MIT) and MenuBarHider
(`happy666End/MenuBarHider`, MIT) are built on it. Reported limits:
- It works per app.
- Processes without a bundle identifier can't be allowlisted (dwarvesf/hidden #465, on 27.2).
- Apps outside `/Applications` are ignored.

## Goals

1. On macOS 27, hiding the hidden section makes the apps the owner put left of
   the hidden divider disappear from the bar, with no stretched divider, no
   blank, and no `«` needed for them.
2. Hovering over the Lynx icon shows them in the bar. The owner clicks one,
   and they hide again by the usual rules.
3. The owner chooses the hidden apps by ⌘-dragging icons across the divider
   while the section is shown, as on macOS 26.
4. The choice survives relaunches and restarts.
5. If the facility is unavailable, Lynx Bar behaves exactly as it does today
   (round B) and says why.

## Non-goals

- Hiding a single icon of an app that has several. The allowlist is per app.
- Search, the Menu Bar Layout pane, the Shelf panel and item images on 27.
- Changing anything on macOS 14–26. Every change sits behind
  `#available(macOS 27.0, *)`, placed before the macOS 26 checks.
- Mac App Store compatibility. This is a private API.

## Anti-goals

These would make the feature a failure even if hiding technically works:

- **The Lynx icon itself, or an app icon the owner kept visible, disappears.**
  (Apple's Now Playing and Focus icons are the accepted exception, see Risks.)
  It must always be on the allowlist, and Lynx Bar must refuse to use the
  facility when its own icon would be ignored.
- **Showing on hover reshuffles the bar under the pointer, or loops.** Round B
  removed exactly that.
- **Icons stay hidden after Lynx Bar quits, crashes or is updated.**
- **The pointer moves, or the bar flickers, when nothing was asked for.**

## Constraints

- **Lynx Bar must run from `/Applications`.** From anywhere else the allowlist
  ignores it and hides its own icon. Check `Bundle.main.bundleURL` at launch.
  Anywhere else, don't activate the facility. Use the round-B behaviour and
  show a note in General settings: "Move Lynx Bar to the Applications folder
  to hide items on macOS 27."
- **Positions are only readable while icons are drawn.** Once hidden, an app
  is absent from both agent windows. The hidden list must be worked out from
  the bar's order while everything is shown, and remembered.
- **27.2 quirks, already handled in `MenuBarAgentLayout` (round B):**
  - The agent has two windows. Only the one holding the `«` is the live bar.
    The other lists every item side by side and has no `«`.
  - Window order and child roles swap between launches.
  - Our own status item windows follow the item list, about 56 pt off the
    live slot.
  - So the Lynx icon's real position must come from the live layout, not
    from `controlItem.frame`.
- **Bundle identifiers.** Map each item's owning PID to a bundle identifier
  with `NSRunningApplication`. An item whose process has no bundle identifier
  can't be allowlisted. Never put it in the hidden set: if it stays drawn,
  good; if the system hides it anyway, that's a known limitation.

## Design (decided)

### Which apps are hidden

- The order source is the agent's item-list window, the 27.2 window without
  the `«`. It lists every drawn item left to right with its owning PID.
- An app is in the **hidden set** when any of its items lies left of the
  hidden divider in that order. The same rule with the always-hidden divider
  gives the **always-hidden set**. An app counts in the leftmost section any
  of its items is in.
- **Membership is sticky (my call).** On every hide, Lynx Bar reads the order
  and moves an app between sets only when it sees one of the app's icons on
  the other side of a divider. An app that isn't drawn keeps its membership.
  That covers an app that has quit, or one still under the always-hidden
  assertion. So Teams stays hidden after it's relaunched. The spike showed
  icons come back in the same place after `invalidate`, so the order read at
  each hide reflects the owner's ⌘-drags.
- The sets are stored in `UserDefaults` under new keys, so they apply at
  launch before anything is drawn. At first launch with nothing stored, they
  are read from the current order.
- Lynx Bar's own bundle identifier is never in a hidden set.
- **Apple's items are never hideable (my call).** Items owned by MenuBarAgent,
  Control Center, SystemUIServer or any other `com.apple.*` process are left
  out of both sets, even when dragged left of a divider. The allowlist has no
  per-item control for them.

### Hiding and showing

- **Hide the hidden section:** activate an assertion whose allowed bundle
  identifiers are every app with a status item that is not in the hidden
  set. Lynx Bar is always included, and system items are always `0...255`.
- **Show it:** invalidate the assertion. With the always-hidden section
  enabled and hidden, activate a new assertion that excludes only the
  always-hidden set, rather than leaving no restriction at all.
- **One assertion at a time.** Replace it by activating the new one first,
  then invalidating the old. The spike showed the new one takes effect only
  once the old is invalidated, with no flash in between.
- Requests go through a serial queue, like `SystemOverflow`'s, so quick
  hover/click sequences can't race.
- Dividers keep their standard length on 27 (`HostedHidingWidth.isEnabled`
  stays `false`).
- **"Use Lynx Shelf" on 27 (my call):** showing still opens the `«` if items
  don't fit, as today.

### Building the allowlist

The allowlist is a list of apps to *show*, so hiding has to name every app
that should stay visible:
- Every app that currently has a status item in the agent's windows, minus
  the hidden set.
- Lynx Bar itself.
- Every running regular or accessory app's bundle identifier (my call). This
  keeps apps visible whose icon appears while the section is hidden.
  Hidden-set apps are always excluded.

### Show on hover, on the Lynx icon only

- On macOS 27 with the facility active, show on hover fires when the pointer
  rests on the **Lynx icon**, after the existing "Show on hover delay", and
  not on empty space.
- The Lynx icon's frame comes from the live layout's own slots, not from the
  control item's window frame.
- **Rehiding after a hover-show** follows the macOS 26 rules: the pointer
  leaving the menu bar, the rehide strategy, or a click.
- **Except while a revealed app's menu is open (my call).** Removing a status
  item closes its menu, so rehiding waits until that menu closes. Otherwise
  moving the pointer down into the menu would close it, which breaks "click
  the one they want". Detecting the open menu is left to the builder.
- Revealed icons must not slide under the pointer and retrigger anything.
  Showing doesn't move the Lynx icon if the hidden apps sit left of the
  divider, so no loop is expected. Verify this by hand.
- The settings toggle "Show on hover" comes back on 27 when the facility is
  active. Its note says it works on the Lynx icon on macOS 27.
  `GeneralSettings.isShowOnHoverActive` becomes "facility active" on 27,
  instead of always `false`.

### Safety and recovery

- **Normal quit:** invalidate in `applicationWillTerminate`.
- **Crash or kill:** the assertion dies with the process. The spike showed it
  is tied to the process.
- **Sleep and wake, display changes:** keep the assertion; re-apply after
  wake if the system dropped it. Detect that by an app from the hidden set
  being drawn while the section is hidden.
- **A new app appears while the section is hidden:** its icon shows, because
  it isn't in the hidden set. It takes its position, and the next hide
  recomputes the sets.

### Availability and fallback

- `HostedAllowlist.isAvailable` is true when all of these hold:
  - macOS 27 or later
  - the framework loads
  - both classes and all four selectors exist
  - Lynx Bar runs from `/Applications`
- If activation reports an error, log it, invalidate, fall back to round-B
  behaviour for the session, and show the note in General settings.

### Suggested structure (builder may change)

- `MenuBar/Hosted/HostedAllowlist.swift`: the Objective-C runtime calls
  (`dlopen`, `alloc`/initializers, `activate`/`invalidate`) and availability.
  No logic.
- `MenuBar/ControlItem/HostedSections.swift`: pure, tested logic.
  - Inputs: ordered items as (bundle ID or `nil`, frame, isOwn), the divider
    slots, Lynx Bar's bundle ID, and the running apps.
  - Outputs: the hidden and always-hidden sets, and the allowlist for a given
    section state.
- `MenuBarSection.show()` / `hide()` call into a small `@MainActor` manager on
  macOS 27 when the facility is available. Otherwise they do what they do
  today.
- New `Defaults` keys for the two sets. New keys may use Lynx Bar's own names;
  never rename existing keys.

## Left to the builder

- How to read the item-list window's order robustly: it is the agent window
  without the `«` identifier. With no `«` at all, the two windows match while
  everything is shown; take either.
- Exact timing and debouncing of the hover-show on the Lynx icon.
- Whether the always-hidden section needs any hotkey or option-click changes
  (none expected).
- Log messages: debug for every activate and invalidate with the set sizes;
  error for failures.

## Testing

- **Script tests (`Scripts/run-tests.sh`), for `HostedSections`:**
  - Hidden and always-hidden sets from orders measured on 27.2. Use the
    layouts in `Scripts/Tests/HostedOverflow`, extended with bundle IDs.
  - An app with items on both sides of a divider.
  - Lynx Bar never hidden.
  - Items without a bundle ID never in a set.
  - The allowlist for each section state.
- **By hand, macOS 27.2, from `/Applications`:**
  - Teams, OneDrive, Rocket.Chat and Ollama ⌘-dragged left of the divider
    hide when the section hides.
  - Hovering the Lynx icon shows them, a click on one opens its menu, and
    they rehide by the rehide strategy.
  - Relaunching keeps the choice.
  - Quitting, and `kill -9`, both restore everything.
  - Running from `~/Applications` shows the note and keeps round-B behaviour.
  - Sleep and wake.
  - The always-hidden section on.
- `swiftlint --strict`, Debug build, `Scripts/check-names.sh`.

## Risks

- **A private API can change or vanish in any macOS update.** Mitigated by
  the availability check and the fallback, and by checking selectors at
  runtime rather than assuming them.
- **Per-app granularity may surprise.** Hiding one app hides all of its
  icons. Document it in `FREQUENT_ISSUES.md`.
- **Apps outside `/Applications`, and processes without a bundle ID,** may be
  hidden while the section is hidden even if they sit right of the divider.
  Document it.
- **Apple's Now Playing and Focus icons hide too** while any assertion is
  active, and nothing tried keeps them. The owner accepted this (2026-11-10).
  Document it in `FREQUENT_ISSUES.md`. If a later macOS lets them through,
  nothing needs to change.
- **Other menu bar managers using the same facility** (Hidden Bar, Stash)
  could fight over it. Document that only one should run.
