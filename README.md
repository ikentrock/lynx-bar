<div align="center">
    <img src="LynxBar/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
    <h1>Lynx Bar</h1>
</div>

Lynx Bar is a menu bar manager for macOS 14 and later. It hides and shows menu bar items,
shows hidden items in the **Lynx Shelf** below the menu bar (handy on notched MacBooks),
lets you arrange items by dragging, search them, and change the menu bar's appearance.

Lynx Bar is a fork of [Ice](https://github.com/jordanbaird/Ice) by Jordan Baird, based on
Ice's unreleased macOS 26 work, and is licensed under the [GPL-3.0](LICENSE) like Ice.

> [!NOTE]
> There are no release downloads yet. Build it yourself as described below.

## Build it yourself

You need macOS 14 or later and Xcode (the full app, not only the Command Line Tools).

1. **Create a code-signing certificate (once).** Lynx Bar's helper only talks to an app
   signed with the same certificate, and macOS only keeps Lynx Bar's permissions across
   rebuilds when it's signed with a certificate. A free self-signed one is enough:
   Keychain Access → Certificate Assistant → Create a Certificate…, choose a name, Identity
   Type **Self Signed Root**, Certificate Type **Code Signing**. It's fine that Keychain shows
   it as "not trusted".
2. **Point the build at it.** `cp Config/Local.xcconfig.example Config/Local.xcconfig`, then
   set `CODE_SIGN_IDENTITY` to your certificate's name. This file is gitignored.
3. **Build.**

   ```sh
   xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Release build
   ```

   Copy `Lynx Bar.app` from the build products into `/Applications` (or `~/Applications`).
4. **Grant permissions.** On first launch Lynx Bar asks for Accessibility (required) and
   Screen Recording (for the Lynx Shelf and item images). Quit and reopen it after granting
   Screen Recording.

Without a certificate the build still succeeds, but Lynx Bar can't start its helper and shows
a message in place of your menu bar items.

## Coming from Ice

On first launch Lynx Bar copies your Ice settings (sections, hotkeys, appearance, shelf
settings). Ice's own settings aren't changed. Permissions and "Launch at login" need to be
set again.

## License

Lynx Bar is available under the [GPL-3.0 license](LICENSE). It is based on Ice, © Jordan
Baird, also GPL-3.0.
