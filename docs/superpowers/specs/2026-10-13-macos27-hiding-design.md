# macOS 27 support, round A: hiding works again

Date: 2026-10-13
Status: design, awaiting review

## Goal

On macOS 27 Lynx Bar is broken: the hidden section is never hidden, and the
Lynx Shelf, search and layout panes stay on "Loading menu bar items…" forever.
Round A makes the core work on 27: hiding and showing the hidden and
always-hidden sections by click, hotkey and auto-rehide. Every feature that
needs the list of menu bar items (Shelf, search, item images, layout arranger)
is turned off on 27 and says so, instead of hanging.

macOS 14–26 behaviour must not change.

Out of scope (round B): listing menu bar items on 27, then the Shelf, search,
images and moving items.

## What changed in macOS 27

Measured on 27.0.1 (build 26A434), one 1920 × 1080 pt display without a notch,
with throwaway probe scripts that were not kept:

1. **No window per item.** A new `/System/Library/CoreServices/MenuBarAgent.app`
   draws the status area as one window per display. `CGSGetProcessMenuBarWindowList`
   returns only that window, and `CGWindowList` has no per-item status windows,
   not even Lynx Bar's own. `MenuBarItem.getMenuBarItems` therefore finds
   nothing, `ControlItemPair` is `nil`, and the cache stays empty ("Missing
   control item for hidden section").
2. **Items can't be pushed off the screen any more.** A stretched divider
   squeezes the items on its left towards the app menus. Items that don't fit
   go into the system's own overflow: a `«` button owned by `MenuBarAgent`
   (Accessibility description "Show Hidden Menu Bar Items") that appears next to
   the app menus. That overflow is the only way an item gets hidden on 27.
3. **Items wider than half the display are discarded.** A divider of 900 pt
   stayed in the bar. From 950 pt, more than half of 1920, it vanished from the
   bar and everything it had hidden came back. Lengths are also capped at about
   5,000 pt.
4. **A divider stretched before it has a place lands outside the bar.** A status
   item created at 10,000 pt sits at `y=1084` (Accessibility) or
   `y=-33` (its AppKit window). Lynx Bar's real hidden divider was found in that
   state. Setting the length back to a normal value brings it back into the bar.
5. **Our own frames are still usable.** The AppKit window frame of our own
   status item matches its position in the bar (probe: window 1531–1567 against
   Accessibility 1538–1560, which includes the agent's padding).
6. **Accessibility still lists items.** `MenuBarAgent`'s Accessibility tree has
   one slot per item, hidden ones included, and every app's `AXExtrasMenuBar`
   reports its items with frames. This is for round B and is not used here.
7. **The system's per-app menu bar switches can't be used.** They're stored in
   `~/Library/Group Containers/com.apple.MenuBar`, which macOS blocks even from
   reading ("Operation not permitted").

## Prior art

[IceMelt](https://github.com/pnikolaidis/icemelt), another GPL-3.0 fork of Ice,
solved the same problem in
[PR #46](https://github.com/pnikolaidis/icemelt/pull/46) (merged 2026-09-30):
size the divider to the room between the app menu and the visible items, so
the whole section overflows. Round A ports that hiding approach. Its item
listing, which reads `MenuBarAgent`'s tree in the helper, is left for round B.
Ported code keeps IceMelt's copyright notice and is credited in the commit
messages and in a new credit line in the README. Both projects are GPL-3.0.

## Design

### Version gating

Add a `#available(macOS 27, *)` check wherever 27 needs different behaviour.
It must come **before** any existing `#available(macOS 26.0, *)` check, because
those checks are also true on 27. Code that runs only on 14–26 is not touched.

### Hiding width: `HostedHidingWidth`

New file `LynxBar/MenuBar/ControlItem/HostedHidingWidth.swift`, all pure
functions so that a script test can cover them:

- `width(visibleFrom: CGFloat, regionLeft: CGFloat) -> CGFloat`
  returns `max(visibleFrom - regionLeft - 8, 0)`. `visibleFrom` is the x where
  items that must stay visible begin. `regionLeft` is where the agent's item area
  begins. The 8 pt margin must be narrower than any item, or the section's last
  item stays in the bar.
- `length(width: CGFloat?, screenWidth: CGFloat) -> CGFloat`
  turns that into the `NSStatusItem.length` to set. It subtracts the agent's
  16 pt padding and caps the result at `floor(screenWidth / 2) - 16`, so the
  divider is never discarded. With no measurement yet it uses the cap.
- `shouldApply(old: CGFloat?, new: CGFloat) -> Bool`
  is false when the change is under 8 pt. Every length change reflows the bar,
  so small changes are ignored.

The 8 and 16 pt values come from IceMelt and are checked by hand on this
display.

### Measuring on 27

A new `@Published var hostedHidingWidths: [ControlItem.Identifier: CGFloat]`
on `MenuBarItemManager`, filled by `updateHostedHidingWidths()`. That's a
macOS 27 method that doesn't need the item list:

- **`regionLeft`.** The right edge of
  `NSScreen.screenWithActiveMenuBar.getApplicationMenuFrame()` (existing helper),
  moved past the notch if `frameOfNotch` is set, plus the agent's 16 pt
  padding.
- **`visibleFrom` for a divider in the bar.** The right edge of the divider's own
  window (`ControlItem.frame`, already published). The divider grows leftwards,
  so its right edge is the left edge of the items that stay visible.
- **A divider that isn't in the bar.** Its window frame lies outside the
  menu bar (finding 4) or it has no window. Set its length to standard, let the
  next measurement run with the divider back in the bar, then apply the
  hiding length. Log it once each time.

`ControlItem` (hidden and always-hidden only) subscribes to its entry in
`hostedHidingWidths` on 27 and recomputes its length. On 14–26,
`Identifier.length(for:)` still returns `Lengths.expanded` (10,000). On 27 the
"hide" length comes from `HostedHidingWidth.length`.

### When to measure on 27

- When the frontmost app changes (`NSWorkspace.didActivateApplicationNotification`),
  because the app menu's width changes.
- When the screen layout or the active menu bar display changes.
- About 600 ms after a section shows or hides, because what's in the bar changes
  (as IceMelt's `recacheAfterStateChange`).
- Debounced so that a burst of events causes one measurement.

Measuring only sets `statusItem.length`. It doesn't change any section's
hiding state and doesn't run rehide timers.

### Item list and helper on 27

- `MenuBarItemManager.helperFailureReason` becomes `itemsUnavailableReason`
  with the same behaviour: no caching, no moving, and the message shown instead
  of items. It's set by a helper failure (existing message) or, on 27, at
  startup with "Showing menu bar items isn't supported on macOS 27 yet." The
  Shelf, search panel and layout pane already show this message instead of
  "Loading…" through their existing checks, which get renamed.
- On 27 the `MenuBarItemService` helper isn't started, because nothing uses it
  in round A.
- On 27 the Lynx Shelf counts as off. `MenuBarSection.useLynxShelf` returns
  `false`, so clicking the Lynx icon shows the section in the bar. The stored
  `UseIceBar` setting isn't changed, so it comes back with round B or on an
  older macOS. The General pane disables the Shelf toggle on 27 and shows the
  same note.
- Hidden items can still be reached through the system's `«` overflow button.

## Known limitations on 27 (round A)

- **Wide displays.** Because of the half-display cap, when the room left of the
  visible items is wider than half the display, the first hidden items stay in
  the bar. That happens on very wide screens with few visible items. The
  1920 pt test display is only affected with very few visible items.
- **Always-hidden.** While both sections are hidden, everything is in the same
  overflow. The always-hidden section only gives extra hiding when the hidden
  section is shown.
- **Several displays.** Widths are measured for the display with the active
  menu bar, as in IceMelt.

## Testing

- **Script test** `Scripts/Tests/HostedHidingWidth/`, run by
  `Scripts/run-tests.sh`, covering `width`, `length` and `shouldApply`: normal
  room, room smaller than the margin (0), the half-display cap, no measurement
  (cap), and changes just under and over 8 pt.
- **Manual check on macOS 27** with a certificate-signed build:
  1. Launch with the hidden section hidden. The divider stays in the bar, the
     hidden items are gone, and they're listed behind the system `«`.
  2. Show and hide by clicking the Lynx icon, then by hotkey.
  3. Auto-rehide after the timeout.
  4. Always-hidden: hide only it, then both, then show both.
  5. While hidden, switch between an app with short menus (Finder) and one with
     long menus (Mail or Xcode). Items stay hidden, the divider is never
     discarded, and after a switch the bar settles without flickering back and
     forth.
  6. The Shelf, search and layout pane show the "not supported on macOS 27"
     message instead of "Loading…".
  7. Start Lynx Bar from the broken state (divider at `y=1084`). It recovers
     into the bar.
- **No regression on 14–26:** `swiftlint --strict`, `Scripts/run-tests.sh`,
  `Scripts/check-names.sh` and a Debug build pass. There's no machine with
  macOS 26 or earlier, so this is checked by review: every 27 change sits behind
  an `#available(macOS 27, *)` check placed before the macOS 26 checks.

## Risks

- The 8 pt margin and 16 pt padding are tuned on one display without a notch.
  Notched laptops are handled by `frameOfNotch` but aren't tested here.
- A later macOS 27.x may change the overflow rules or the half-display limit.
  The log line for a divider found outside the bar makes that visible.
- Reflow loops: applying a length moves items, which triggers another
  measurement. The 8 pt threshold and the debounce are what prevent a loop.
  Manual check 5 covers this.
