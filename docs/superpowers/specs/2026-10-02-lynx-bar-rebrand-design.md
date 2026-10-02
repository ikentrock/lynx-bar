# Lynx Bar: fork base and rebrand (Step 1)

Status: draft for review · 2026-10-02

## Goal

Make this fork its own app, **Lynx Bar**. It should no longer identify as Ice, update from Ice,
or depend on Ice's Apple Developer team. It must also work on the macOS 26 machine it is
developed on. The Ice Bar matters most, because it's the feature the owner wants to use.

The work happens in two steps:

1. **Step 1 (this spec):** choose the base and rebrand everything users see, without renaming the
   internals.
2. **Step 2 (separate spec):** a purely mechanical rename of internal identifiers: the `Ice`
   target and scheme, folders, type names like `IceBar`, and the `//  Ice` file headers.

New features and further macOS 26 fixes are out of scope and get their own specs.

## Audience and distribution

For now Lynx Bar is built locally for the owner. It must be easy to move to public releases
later: updates are off, and there are obvious places for a Developer ID team and a Sparkle feed.
The owner has no paid Apple Developer account, so builds are signed with a self-signed
certificate.

## Findings that shaped this design

These were measured on macOS 26.6.2 with Xcode 27.0 on 2026-10-01/02.

- **Ice 0.11.12 (`upstream/main`) does not work on macOS 26.**
  - It crashes when a section is shown. `ControlItem.windowID` converts a negative
    `NSWindow.windowNumber` with `CGWindowID(_:)`, which traps.
  - With the crash fixed, the Ice Bar is still empty. On macOS 26 every menu bar item window,
    including Ice's own dividers, is owned by Control Center. 0.11.12 identifies items by
    (owner bundle ID, title), so it never finds its hidden-section divider and clears its item
    cache.
- **`upstream/macos-26`** (77 commits ahead of `main`, last updated 2025-09-20) already solves
  item identity. It adds a `MenuBarItemService` XPC helper and a `SourcePIDCache` that maps
  windows to their source apps through Accessibility.
  - It hung at "Loading menu bar items…" for us, because helper and app each require
    `.isFromSameTeam()`. Ad-hoc and self-signed builds have no team ID, so every connection
    is rejected ("Dropping check-in message due to code signing requirement").
- **A spike confirmed the replacement trust check.** "Same signing certificate + expected
  identifier", using `xpc_connection_set_peer_code_signing_requirement`:
  - A self-signed app and helper connect, and the Ice Bar shows items.
  - An ad-hoc helper refuses all connections.
  - A helper signed with the right certificate but the wrong identifier is refused by the app
    ("Peer Forbidden").
  - The spike code is in `~/Library/Caches/lynx-bar-dev/spike-macos26` (throwaway).
- **No CompactSlider 1.x release compiles with the Xcode 27 SDK.**
  `ProminentCompactSliderStyle.swift` makes an ambiguous `opacity` call (`View` vs
  `ShapeStyle`). 2.x compiles, but has a different API.
- **macOS permissions and test builds.** Accessibility and Screen Recording grants are tied to
  the signature. Ad-hoc builds lose them on every rebuild, while a certificate-signed build
  keeps them. Several apps all named "Ice" in System Settings made it unclear which toggle
  belonged to which build.

## Decisions

| Topic | Decision |
|---|---|
| Base | `upstream/macos-26` |
| App name | Lynx Bar |
| Bundle ID | `com.ikentrock.LynxBar` |
| Helper bundle ID | `com.ikentrock.LynxBar.MenuBarItemService` |
| Version | `0.12.0` (build number continues upstream's) |
| Copyright | "© Luisen Ramos. Based on Ice by Jordan Baird." (GPL-3.0 notice kept, modification stated) |
| Updates | Off; Sparkle stays linked, with no feed configured |
| Ice settings | Imported once on first launch |
| Artwork | Placeholder lynx app icon and menu bar glyph, made in this step |
| Ad-hoc builds | Supported for compiling, but the helper connection is refused, with a clear message |

## Design

### 1. Base and branches

- Merge `upstream/macos-26` into this repo's `main` as a normal merge commit, with no
  force-push. `main` only adds `CLAUDE.md` and two issue-template commits, so conflicts are
  limited to `.github/ISSUE_TEMPLATE/*`, which the rebrand rewrites anyway.
- Work happens on the `lynx-bar-rebrand` branch and merges into `main` when done.
- Branch `fix/xcode27-and-windowid-crash` is not merged. Its crash fix targets code that
  `macos-26` rewrote (no `windowNumber` conversions remain), and its vendoring targets
  CompactSlider 1.1.6. It stays as a record until the owner deletes it.

### 2. Build fix: vendored CompactSlider

- `macos-26` pins CompactSlider **1.2.1**. Vendor that exact revision into
  `Packages/CompactSlider` as a local Swift package (keeping `LICENSE` and `README.md`). Apply
  the one-line patch that wraps the gradient in `Rectangle().fill(...)`, and add `VENDORED.md`
  recording the revision and the patch.
- Change the project reference from remote to local, and remove the `compactslider` pin from
  `Package.resolved`.

### 3. Identity and build settings

- App `PRODUCT_NAME = "Lynx Bar"`, so the bundle and executable are `Lynx Bar.app` and Finder
  and Activity Monitor show "Lynx Bar". `PRODUCT_MODULE_NAME = Ice` is set explicitly, so the
  Swift module (and anything module-qualified) keeps its name until Step 2. The target and
  scheme names also stay `Ice` until then.
- One tracked build setting, `LYNX_BUNDLE_ID = com.ikentrock.LynxBar` in
  `Config/Base.xcconfig`, drives both targets: the app uses `$(LYNX_BUNDLE_ID)` and the helper
  `$(LYNX_BUNDLE_ID).MenuBarItemService`.
- `DEVELOPMENT_TEAM` is emptied for both targets.
- **Signing config.** A tracked `Config/Base.xcconfig` optionally includes a gitignored
  `Config/Local.xcconfig` (`#include? "Local.xcconfig"`) containing, for example,
  `CODE_SIGN_IDENTITY = Luisen` and `CODE_SIGN_STYLE = Manual`. Without it, builds are ad-hoc.
  Xcode signs nested code (the helper), so nothing is re-signed by hand.
  - Verified on the spike: `xcodebuild CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=Luisen
    DEVELOPMENT_TEAM=` signs both the app and the embedded helper with the self-signed
    certificate, even though Keychain reports it as not trusted. No "Always Trust" step is
    needed.
- **No hardcoded helper name.** The identifiers are derived at runtime, so there's no
  constant to drift (the mismatch that broke the spike's first runs):
  - The app computes the service name as `Bundle.main.bundleIdentifier + ".MenuBarItemService"`.
  - The helper computes its host identifier by removing that suffix from its own bundle
    identifier.
  - `MenuBarItemService.name` becomes a computed property.
- `MARKETING_VERSION = 0.12.0` and the copyright string are set in the build settings.

### 4. Helper trust: same certificate + expected identifier

Each side computes its peer requirement **from its own signature** at launch:

| Own signature | Requirement placed on the peer |
|---|---|
| Team ID present | `anchor apple generic and certificate leaf[subject.OU] = "<team>" and identifier "<peer>"` |
| Certificate, no team (self-signed) | `certificate leaf = H"<own leaf SHA-1>" and identifier "<peer>"` |
| Ad-hoc / unsigned | none: refuse to connect |

- **New `Shared/Services/PeerCodeRequirement.swift`.** It reads the process's own signing
  information (`SecCodeCopySelf` → `SecCodeCopySigningInformation`) and builds the string
  above, or returns `nil`.
- **App side (`MenuBarItemServiceConnection.swift`).** Replace `XPCSession` with
  `xpc_connection_create` and set `xpc_connection_set_peer_code_signing_requirement` with the
  helper's identifier before resuming. Requests and replies stay the existing `Codable`
  `Request`/`Response` enums, carried as JSON data under one dictionary key. The public
  `Connection` API (`start()`, `sourcePID(for:)`) is unchanged, so callers don't change.
  Unlike the spike, connection state changes happen only under the existing lock.
- **Helper side (`Listener.swift`, `main.swift`).** Replace `XPCListener` with `xpc_main`.
  `RunLoopType` is already `NSRunLoop`, so `SourcePIDCache` keeps its run loop. Every
  incoming connection gets the host-app requirement, or is cancelled if the helper has no
  usable signature.
- **macOS 14/15.** Upstream used no requirement there. Lynx Bar applies the same requirement
  on every OS version; `xpc_connection_set_peer_code_signing_requirement` is available
  since macOS 12.
- **When the connection is refused** (ad-hoc build or a mismatched signature), the app logs
  the reason once and the Ice Bar, Layout pane and search show "Lynx Bar's helper couldn't
  start. Build Lynx Bar with a signing certificate (see README)." in place of a spinner that
  never ends. In this state the item manager neither caches nor moves items.

### 5. Updates (off, ready to switch on)

- Remove `SUFeedURL` and `SUPublicEDKey` from `Ice/Resources/Info.plist`.
- `UpdatesManager` (`Ice/Main/Updates.swift`) checks whether `SUFeedURL` is present. Without
  it, Sparkle is never started, and the Updates section says "Updates are not available in
  this build." Adding a feed URL and key later turns updates back on with no code change.

### 6. Importing Ice settings

- New `IceSettingsImporter` runs at launch **before** `Migration.migrateAll()`. Ice's stored
  formats then still pass through upstream's migrations (for example `migrate0_11_13`, which
  rewrites control item position keys).
- The import runs only if `hasImportedIceSettings` isn't set. If Ice's persistent domain
  (`persistentDomain(forName: "com.jordanbaird.Ice")`) has data, it copies every key that Lynx
  Bar doesn't already have. Either way it then sets the flag, so the import happens on the
  first launch or never. Ice's domain is only read. It deliberately
  doesn't check for an "empty" Lynx Bar domain, because anything that writes a default before
  the importer runs would silently skip the import.
- Login-item state is stored per app by macOS, so it isn't imported and starts off.
- Accessibility and Screen Recording must be granted again, because macOS ties them to the
  bundle ID. The existing permissions window covers this.

### 7. Branding: UI and repo

- User-facing "Ice" strings become "Lynx Bar": window titles, About, Quit, permissions text,
  alerts and the menu bar item's accessibility label. Code identifiers, log categories and
  stored keys (`Ice.ControlItem.*`, `IceIcon`, `UseIceBar` and so on) stay as they are until
  Step 2. Stored keys never change, so saved settings keep working.
- **Feature names.** The "Ice Bar" becomes the **"Lynx Shelf"** and the "Ice icon" becomes the
  **"Lynx icon"**, because "Lynx Bar Bar" would be confusing. Decided 2026-10-02.
- About pane:
  - The repo link goes to `https://github.com/ikentrock/lynx-bar`.
  - "Support Ice" is removed.
  - A "Based on Ice by Jordan Baird" credit links to the upstream repo.
  - The Acknowledgements PDF is unchanged. It already credits CompactSlider, and the
    vendoring is recorded in `Packages/CompactSlider/VENDORED.md`.
- **Menu bar glyph.** A new "Lynx" control-item image set (a template image) becomes the
  default. The "Ice Cube" option is removed from the picker, and a stored "Ice Cube" value
  decodes to "Lynx", so imported settings keep working.
- **App icon.** A placeholder lynx icon at every `AppIcon.appiconset` size, generated from
  one SVG source committed to `Resources/Artwork/`.
- **Repo.**
  - The README is rewritten for Lynx Bar: what it is, credit to Ice, macOS 14+, and "Build it
    yourself" (create a self-signed code-signing certificate, then `Config/Local.xcconfig`).
  - `.github/FUNDING.yml` is removed, and the issue templates point at this repo.
  - `FREQUENT_ISSUES.md` says "Lynx Bar" and links upstream issues as such.
  - `CLAUDE.md` is updated for the new layout (`MenuBarItemService`, `Shared/`, signing,
    and calling `/usr/bin/log`, since zsh's `log` builtin shadows it).

### 8. Out of scope for Step 1

- Internal renames (Step 2).
- New features.
- Pre-existing SwiftLint violations from newer SwiftLint rules
  (`legacy_swiftui_aspect_ratio`, `superfluous_disable_command`) in files this step doesn't
  otherwise touch.
- Any remaining macOS 26 behavior problems found during testing. They are listed, not fixed,
  unless they block the tests below.
- A Sparkle feed, notarization and a release workflow.

## Testing

There is no test target, so verification is a scripted build plus a manual checklist on the
development Mac.

1. **Build.** A clean Debug build with `Config/Local.xcconfig` (signed with the "Luisen"
   certificate) and one without it (ad-hoc) both succeed. `swiftlint --strict` reports no
   violations in files changed by this step.
2. **Trust (repeat the spike checks against the real build):**
   - Certificate-signed: the Ice Bar shows hidden items.
   - Helper re-signed ad-hoc: refused, and the UI shows the helper message.
   - Helper re-signed with the certificate under a wrong identifier: the app logs
     "Peer Forbidden" and the UI shows the helper message.
   - Ad-hoc build: no hang; the helper message is shown.
3. **First launch (with Ice's settings present):** settings imported once (sections, hotkeys,
   Ice Bar choice), the Lynx glyph shown, and the permissions window shown.
4. **Rebuild:** after rebuilding with the certificate, permissions are kept.
5. **Updates:** the Updates section says updates are unavailable. During the first two
   minutes after launch, `nettop -p <pid> -L 1` shows no connection to
   `jordanbaird.github.io`, and `/usr/bin/log` shows no Sparkle update check.
6. **Identity:** System Settings, the About pane, Activity Monitor and the menu bar item's
   accessibility label all say "Lynx Bar". `git grep -i "jordanbaird"` matches only the
   credits and the upstream remote.

## Risks

- **Unfinished upstream work.** `macos-26` is an unreleased branch, and other behavior may be
  rough. Mitigation: the testing checklist exercises the Ice Bar and the Layout pane, and
  problems are written down for later specs.
- **The C XPC API is less ergonomic** than `XPCSession`. Mitigation: it's limited to two files
  behind an unchanged `Connection` API.
- **Untested on macOS 14/15.** Applying the peer requirement there changes behavior that
  upstream left unchecked, and only macOS 26 is available for testing. Mitigation: the code
  path is identical on every version; regressions get reported and fixed later.
- **The spike moved a real menu bar item.** During a negative-test run the item manager logged
  moving the OneDrive item next to the Microsoft 365 Copilot item, presumably while enforcing
  the section order. Item moves on a half-working connection are a hazard. Mitigation: when
  the helper is refused, the item manager must not move items (part of the "helper couldn't
  start" state in section 4).
- **No upstream merges.** Upstream is effectively abandoned, so later upstream changes won't
  merge cleanly after Step 2. This is accepted.
