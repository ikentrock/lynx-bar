# Lynx Bar: internal rename (Step 2)

Status: draft for review · 2026-10-02

## Goal

Finish making the fork its own codebase. After Step 1 (rebrand, see
`2026-10-02-lynx-bar-rebrand-design.md`) users only see "Lynx Bar", but the code is still
organised and named as Ice: the `Ice/` folder, `Ice.xcodeproj`, the `Ice` scheme, target and
module, 27 `Ice*` types, about 30 `ice*` identifiers, and `//  Ice` headers in 105 files.
Step 2 renames all of that to Lynx Bar's vocabulary, **without any behavior change**.

Success means a contributor reading the code meets the names they see in the app (Lynx Bar,
Lynx Shelf, Lynx icon). The app also builds, tests, lints and runs exactly as before, with the
user's settings, permissions and helper connection untouched.

Accepted cost: upstream Ice changes will no longer merge cleanly (the spec for Step 1 already
accepted this; upstream is effectively abandoned).

## Decisions

| Topic | Decision |
|---|---|
| Naming scheme | `Lynx` prefix for the shared UI kit and colors, `LynxShelf` for the bar family, `LynxBar` for the app and project |
| Folder, project | `Ice/` → `LynxBar/`, `Ice.xcodeproj` → `LynxBar.xcodeproj` |
| Scheme, target, module | `LynxBar`. `PRODUCT_MODULE_NAME` is removed (the module follows the target name). `PRODUCT_NAME` stays `"Lynx Bar"`. |
| File header | `//  LynxBar` for files under `LynxBar/` (Shared and helper keep their folder names) |
| Method | Scripted rename from an explicit name table, in four commits, each built and tested |

## What must not change

These are user data or deliberate references. The rename must leave them untouched, and
the final check allowlists them.

- **Stored keys and raw values:**
  - `Defaults.Key` raw values (`"ShowIceIcon"`, `"IceIcon"`, `"CustomIceIconIsTemplate"`,
    `"UseIceBar"`, `"IceBarLocation"`)
  - `HotkeyAction` raw value `"EnableIceBar"`
  - control item identifiers `"Ice.ControlItem.Visible/Hidden/AlwaysHidden"`
  - `IceSettingsImporter.importedFlagKey` (`"hasImportedIceSettings"`)
  - Only the Swift case names around them change, e.g. `case showLynxIcon = "ShowIceIcon"`.
- **Bundle IDs and the product name:** `com.ikentrock.LynxBar`,
  `com.ikentrock.LynxBar.MenuBarItemService`, and `Lynx Bar.app`. Because the bundle ID doesn't
  change, settings and permissions survive.
- **The helper:** the `MenuBarItemService` target, folder and name.
- **Real references to Ice:**
  - `IceSettingsImporter` (it imports from Ice) and its `sourceDomain` (`com.jordanbaird.Ice`)
  - `ControlItemImageSet.Name.legacyIceCube` (`"Ice Cube"`)
  - the About pane's "Based on Ice" button and upstream URL
  - the hotkey registry's Carbon signature `OSType(1231250720)` (`'Ice '`). It's an
    in-process tag, never persisted; it's kept and its comment is updated to say so.
- **Upstream remote, `LICENSE`, `Packages/`, and the historical docs in `docs/superpowers/`.**
- **Codable formats.** None of the renamed identifiers is an encoded stored property (checked
  2026-10-02: the only matches in `Codable` files are statics), and `IceBarLocation` is stored
  as its `Int` raw value. Renaming types doesn't change any stored data.

## Name table

### Folders and files

| Before | After |
|---|---|
| `Ice/` | `LynxBar/` |
| `Ice.xcodeproj` | `LynxBar.xcodeproj` |
| `Ice.xcodeproj/xcshareddata/xcschemes/Ice.xcscheme` | `LynxBar.xcodeproj/xcshareddata/xcschemes/LynxBar.xcscheme` |
| `Ice/MenuBar/IceBar/` | `LynxBar/MenuBar/LynxShelf/` |
| `Ice/UI/IceUI/` | `LynxBar/UI/LynxUI/` |
| `Ice/Main/IceApp.swift` | `LynxBar/Main/LynxBarApp.swift` |
| `IceBar.swift`, `IceBarColorManager.swift`, `IceBarLocation.swift` | `LynxShelf.swift`, `LynxShelfColorManager.swift`, `LynxShelfLocation.swift` |
| `IceForm.swift`, `IceGradientPicker.swift`, `IceGroupBox.swift`, `IceMenu.swift`, `IcePicker.swift`, `IceSection.swift`, `IceSlider.swift`, `IceWindow.swift` | the same names with `Lynx` replacing `Ice` |
| `Ice/UI/Utilities/IceColor.swift`, `IceGradient.swift` | `LynxColor.swift`, `LynxGradient.swift` |
| `Ice/Utilities/IceSettingsImporter.swift` | unchanged name, moves with the folder |

### Types

| Before | After |
|---|---|
| `IceApp` | `LynxBarApp` |
| `IceBarPanel`, `IceBarColorManager`, `IceBarContentView`, `IceBarHostingView`, `IceBarItemView`, `IceBarItemClickView`, `IceBarLocation` | `LynxShelfPanel`, `LynxShelfColorManager`, `LynxShelfContentView`, `LynxShelfHostingView`, `LynxShelfItemView`, `LynxShelfItemClickView`, `LynxShelfLocation` |
| `IceColor`, `IceGradient`, `IceGradientPicker`, `IceGradientPickerRoot`, `IceGradientPickerHandle` | `LynxColor`, `LynxGradient`, `LynxGradientPicker`, `LynxGradientPickerRoot`, `LynxGradientPickerHandle` |
| `IceForm`, `IceFormToggleStyle`, `IceFormLabeledContentStyle` | `LynxForm`, `LynxFormToggleStyle`, `LynxFormLabeledContentStyle` |
| `IceGroupBox`, `IceMenu`, `IcePicker`, `IceSlider` | `LynxGroupBox`, `LynxMenu`, `LynxPicker`, `LynxSlider` |
| `IceSection`, `IceSectionOptions`, `IceSectionLayout`, `IceSectionDivider` | `LynxSection`, `LynxSectionOptions`, `LynxSectionLayout`, `LynxSectionDivider` |
| `IceWindow`, `IceWindowIdentifier` | `LynxWindow`, `LynxWindowIdentifier` |
| `IceSettingsImporter` | unchanged |

### Identifiers

| Before | After |
|---|---|
| `iceBarPanel` | `shelfPanel` |
| `useIceBar`, `isIceBarPresented`, `screenForIceBar`, `isMouseInsideIceBar`, `enableIceBar`, `iceBarLocation`, `iceBarLocationPicker`, `iceBarOptions` | `useLynxShelf`, `isLynxShelfPresented`, `screenForLynxShelf`, `isMouseInsideLynxShelf`, `enableLynxShelf`, `lynxShelfLocation`, `lynxShelfLocationPicker`, `lynxShelfOptions` |
| `iceIcon`, `showIceIcon`, `customIceIconIsTemplate`, `lastCustomIceIcon`, `defaultIceIcon`, `userSelectableIceIcons`, `isImportingCustomIceIcon`, `isMouseInsideIceIcon`, `iceIconFrame`, `iceIconMenuItem`, `iceIconOptions`, `iceIconPicker` | `lynxIcon`, `showLynxIcon`, `customLynxIconIsTemplate`, `lastCustomLynxIcon`, `defaultLynxIcon`, `userSelectableLynxIcons`, `isImportingCustomLynxIcon`, `isMouseInsideLynxIcon`, `lynxIconFrame`, `lynxIconMenuItem`, `lynxIconOptions`, `lynxIconPicker` |
| `iceFormDefaultPadding`, `iceFormDefaultSpacing`, `iceGroupBoxDefaultPadding`, `iceSectionDefaultSpacing` | `lynxFormDefaultPadding`, `lynxFormDefaultSpacing`, `lynxGroupBoxDefaultPadding`, `lynxSectionDefaultSpacing` |
| `hasImportedIceSettings`, `legacyIceCube` | unchanged |

`iceIcon` is both a `GeneralSettings` property and a `IceBarLocation` case
(`case iceIcon = 2`). The case is stored by its `Int` raw value, not its name, so both rename.

### Text

- Comments and doc comments that describe this app ("the Ice Bar", "Ice icon", "Ice's
  control items") use Lynx vocabulary. Comments that are about upstream Ice keep "Ice".
- Log messages that describe this app follow the same rule (e.g. "Error decoding Ice icon"
  becomes "Error decoding Lynx icon").

## Approach

A scripted rename driven by the name tables above: `git mv` for paths, word-boundary `perl`
replacements from an explicit list (never a blanket `Ice` → `Lynx`), and scripted
`project.pbxproj` and `.xcscheme` edits. It lands in four commits, and each one must build,
pass `Scripts/run-tests.sh`, and lint clean before the next starts:

1. **Project:** folder, `.xcodeproj`, scheme, target, product/module settings, the
   synchronized-group path, and every path that points into `Ice/`:
   - `.swiftlint.yml` (`included`)
   - `Scripts/run-tests.sh` (source paths)
   - `Resources/Artwork/render.swift` (asset paths)
   - `.github/workflows/lint.yml`, if it names paths
   - `Config/` references
   - README and `CLAUDE.md` build commands
2. **Types:** type renames and the file and folder renames that go with them.
3. **Identifiers:** the identifier table.
4. **Text:** headers (`//  Ice` → `//  LynxBar`, and the SwiftLint header rule), comments,
   log text, `CLAUDE.md` and README prose. This commit also fixes the one remaining lint
   violation (`IconResource.swift`, `.aspectRatio(contentMode:)` → `.scaledToFit()`), so
   `swiftlint --strict` is fully clean.

Considered and rejected:
- **Xcode's Refactor → Rename:** it can't be scripted or repeated, and it doesn't cover
  folders, headers or the project file.
- **A single commit:** it can't be reviewed or bisected.

## Testing

There's no test target, so each commit is checked by:

- a clean Debug build of the `LynxBar` scheme with `Config/Local.xcconfig`
- `Scripts/run-tests.sh` (both suites, also with `LYNX_TEST_CERT`)
- `swiftlint --strict`. Commits 1–3 may still show the `IconResource.swift` violation;
  commit 4 must be fully clean.

Final checks:

1. **Allowlist grep.** `git grep -nP '\bIce|ice[A-Z]|[a-z]Ice'` outside `docs/` and `Packages/`
   finds only the items listed in "What must not change", plus prose about upstream Ice.
2. **Behavior unchanged.**
   - The bundle IDs in the built app's and helper's Info.plist are unchanged.
   - `codesign -d -r-` shows the same designated requirements.
   - The app's `CFBundleExecutable` is still `Lynx Bar`.
3. **Live check.**
   - Install the Release build over the current one. Without re-granting permissions, the
     app must:
     - start
     - connect its helper (no "helper unavailable" log line)
     - show the Lynx icon and shelf with items
     - keep the owner's settings (sections, shelf location)
   - Settings → About still shows version 0.12.0.
4. **Run Release once:** `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Release build`.

## Risks

- **Project file edits.** The `pbxproj` refers to the folder through a synchronized root group,
  and the scheme refers to the target by name and blueprint ID. A wrong edit shows up as a
  build failure in commit 1, which is cheap to fix and doesn't spread.
- **Over-matching replacements.** Mitigation: replace only names from the tables, with word
  boundaries, and rely on the allowlist grep. Raw-value strings are checked by name in the
  final review.
- **Derived data and local paths.** `~/Library/Caches/lynx-bar-dev/dd-lynx` caches the old
  project. Build into a fresh derived-data folder after commit 1.

## Out of scope

- New features, behavior changes, and the deferred minors from Step 1's review.
- Renaming the helper or `IceSettingsImporter`.
- Rewriting history or the historical design docs.
