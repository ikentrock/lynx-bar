# Frequent Issues <!-- omit in toc -->

- [Items are moved to the always-hidden section](#items-are-moved-to-the-always-hidden-section)
- [Lynx Bar removed an item](#lynx-bar-removed-an-item)
- [Lynx Bar does not remember the order of items](#lynx-bar-does-not-remember-the-order-of-items)
- [How do I solve the `Lynx Bar cannot arrange menu bar items in automatically hidden menu bars` error?](#how-do-i-solve-the-lynx-bar-cannot-arrange-menu-bar-items-in-automatically-hidden-menu-bars-error)
- [Shown items disappear under the app menus](#shown-items-disappear-under-the-app-menus)
- [Lynx Bar's helper couldn't start](#lynx-bars-helper-couldnt-start)
- [macOS 27: macOS decides which items are hidden](#macos-27-macos-decides-which-items-are-hidden)

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

## macOS 27: macOS decides which items are hidden

macOS 27 hides menu bar items only by moving them into its own overflow (the `«` button
next to the app menus), and only when they don't fit. Apps can't hide other apps' items,
so on macOS 27 Lynx Bar leaves that to macOS: every item shows while there's room, and the
rest go into the `«`. Lynx Bar's dividers keep their normal size there.

With "Use Lynx Shelf" on, showing the hidden section (the Lynx icon, a click or a scroll in
the menu bar) opens the `«`, and hiding it closes it. From macOS 27.2 Lynx Bar presses the
`«` directly; on earlier versions of macOS 27 it clicks it, so the pointer jumps there for a
moment and comes back. From macOS 27.2 the system also opens the `«` by itself when the
pointer rests on it.

Lynx Bar can't list menu bar items on macOS 27 yet, so search and the Menu Bar Layout pane
are turned off there, the Lynx Shelf can't show its own bar, and "Show on hover" isn't
available.

If the Lynx icon ends up inside the `«`, open the `«` and ⌘-drag the Lynx icon out to the
right.
