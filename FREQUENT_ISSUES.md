# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Lynx Bar removed an item](#lynx-bar-removed-an-item)
- [Lynx Bar does not remember the order of items](#lynx-bar-does-not-remember-the-order-of-items)
- [How do I solve the `Lynx Bar cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-lynx-bar-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)
- [Shown items disappear under the app menus](#shown-items-disappear-under-the-app-menus)
- [Lynx Bar's helper couldn't start](#lynx-bars-helper-couldnt-start)
- [macOS 27: hiding items](#macos-27-hiding-items)

## Items are moved to the always-hidden section

By default, macOS adds new items to the far left of the menu bar, which is also the location of Lynx Bar's always-hidden section. Most apps are
configured to remember the positions of their items, but some are not. macOS treats the items of these apps as new items each time they appear. This
results in these items appearing in the always-hidden section, even if they have been previously been moved.

Lynx Bar does not currently restore the positions of individual items. This is tracked upstream in Ice
[#6](https://github.com/jordanbaird/Ice/issues/6) and [#26](https://github.com/jordanbaird/Ice/issues/26).

## Lynx Bar removed an item

Lynx Bar does not remove items. The item likely got placed in the always-hidden section by macOS. Option + click the Lynx icon to show the
always-hidden section, then Command + drag the item into a different section.

## Lynx Bar does not remember the order of items

This is not a bug, but a missing feature. It is tracked upstream in Ice [#26](https://github.com/jordanbaird/Ice/issues/26).

## How do I solve the `Lynx Bar cannot arrange menu bar items in automatically hidden menu bars` error?

1. Open `System Settings` on your Mac
2. Go to `Control Center`
3. Select `Never` as shown in the image below
4. Update your `Menu Bar Items` in `Lynx Bar`
5. Return `Automatically hide and show the menu bar` to your preferred settings

![Disable Menu Bar Hiding](https://github.com/user-attachments/assets/74c1fde6-d310-4fe3-9f2b-703d8ccb636a)

## Shown items disappear under the app menus

Without the Lynx Shelf, showing hidden items expands them inline in the menu bar. When there isn't enough room, macOS places them under the active
app's menus (or the notch). Turn on **Settings → General → Use Lynx Shelf** to show hidden items in a bar below the menu bar instead.

## Lynx Bar's helper couldn't start

On macOS 26, Lynx Bar uses a helper to tell menu bar items apart. The app and the helper only trust each other when they're signed with the same
certificate, so a build without a certificate (ad-hoc) shows this message. See "Build it yourself" in the [README](README.md).

## macOS 27: hiding items

macOS 27 draws every menu bar item in one window and has no official way to hide other apps' items. Lynx Bar hides them through a private facility of the system's menu bar agent (an allowlist of the apps that may show), so hiding works, with the limits below.

- **Choosing what's hidden.** While the section is shown, ⌘-drag apps to the left of the "|" divider. To unhide an app, ⌘-drag it to the right of the "|" while the section is shown. Removing it from the list some other way is undone at the next hide, which reads the list from where the icons sit. Hiding works per app: an app with several icons hides as a whole.
- **Revealing.** Hover over the Lynx icon (with "Show on hover" on) or click it. Hidden apps reappear in place. Rehiding waits while one of the revealed apps has a window open: a menu, popover or panel (a cloud-storage app's panel, for example). Other apps' windows don't hold it. Clicking the Lynx icon right after a hover-reveal hides the section again, since the click toggles it.
- **Lynx Bar must run from `/Applications`.** Otherwise Settings shows "Move Lynx Bar to the Applications folder to hide items on macOS 27." and Lynx Bar falls back to letting macOS decide what hides (the `«` button next to the app menus). Apps outside `/Applications`, or without a bundle ID, may stay hidden while a section is hidden.
- **Now Playing and Focus.** Apple's Now Playing and Focus icons also hide while a section is hidden. That's a macOS limitation.
- **Other menu bar managers.** Don't run another manager that uses the same facility (Hidden Bar, Stash) at the same time.
- **Recovery.** Quitting Lynx Bar brings every icon back.
- **Fallback.** If macOS removes the facility (or Lynx Bar doesn't run from `/Applications`), Lynx Bar falls back to letting macOS decide: every item shows while there's room, and the rest go into the `«`. "Show on hover" is off entirely in the fallback.
- **Lynx Shelf.** With "Use Lynx Shelf" on, showing the hidden section also opens the `«` for items that don't fit, with or without the facility.

Lynx Bar can't list menu bar items on macOS 27 yet, so search and the Menu Bar Layout pane are turned off there and the Lynx Shelf can't show its own bar. "Show on hover" works from the Lynx icon only, and only while hiding through the facility works.

If the Lynx icon ends up inside the `«`, open the `«` and ⌘-drag the Lynx icon out to the right.
