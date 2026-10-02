# Lynx Bar Internal Rename (Step 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the codebase's internal Ice names to Lynx Bar's vocabulary:
- the `Ice/` folder, `Ice.xcodeproj`, and the `Ice` scheme, target and module
- 26 `Ice*` types and about 30 `ice*` identifiers
- the `//  Ice` file headers

There must be no behavior change.

**Architecture:** A scripted rename driven by explicit name tables, in four commits:
1. project
2. types (with their files)
3. identifiers
4. text, headers and a permanent name check

Each commit must build, pass the script tests and lint before the next one starts. Stored
keys, bundle IDs and real references to upstream Ice are deliberately left alone.

**Tech Stack:** Xcode 27 project (synchronized folder groups), Swift 5 mode, Python 3 for the
rename scripts, SwiftLint, the zsh test runner `Scripts/run-tests.sh`.

**Spec:** `docs/superpowers/specs/2026-10-02-lynx-bar-internal-rename-design.md`. It holds
the name tables, the "must not change" list and the reasons behind them; read it first.

## Global Constraints

- **No behavior change.** Bundle IDs stay `com.ikentrock.LynxBar` and
  `com.ikentrock.LynxBar.MenuBarItemService`, and the product stays `Lynx Bar.app`
  (`PRODUCT_NAME = "Lynx Bar"`).
- **Stored keys and raw values never change:**
  - `"ShowIceIcon"`, `"IceIcon"`, `"CustomIceIconIsTemplate"`, `"UseIceBar"`, `"IceBarLocation"`
  - `"EnableIceBar"`
  - `"Ice.ControlItem.Visible/Hidden/AlwaysHidden"`
  - `"hasImportedIceSettings"`
- **Names that stay:**
  - `IceSettingsImporter` and `com.jordanbaird.Ice`
  - `legacyIceCube` / `"Ice Cube"` and `hasImportedIceSettings`
  - the `MenuBarItemService` target, folder and name
  - the About pane's "Based on Ice" button and the `jordanbaird/Ice` URLs
  - `OSType(1231250720)`
- **New names:**
  - folder `LynxBar/`, project `LynxBar.xcodeproj`, scheme and target `LynxBar`, Swift module
    `LynxBar`
  - file header `//  LynxBar` for files under `LynxBar/`
- Replacements use **only** the spec's name tables, with word boundaries. Never do a blanket
  `Ice` → `Lynx`.
- Don't touch `docs/superpowers/` history, `Packages/`, `LICENSE`, or the `upstream` remote.
- Work on branch `lynx-bar-internal-rename`. End every commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- In zsh, call `/usr/bin/log`, not `log`.

## Commands used throughout

```sh
# Build (after Task 1; signs with Config/Local.xcconfig if present)
xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build > ~/Library/Caches/lynx-bar-dev/build.log 2>&1; \
  grep -E "error:|\*\* BUILD" ~/Library/Caches/lynx-bar-dev/build.log | sort -u

# Tests
Scripts/run-tests.sh && LYNX_TEST_CERT=E0ED98F7B2D56951B4E0A99082DEBAF25AF66311 Scripts/run-tests.sh

# Lint (Tasks 1–3 may still show only LynxBar/Utilities/IconResource.swift; Task 4 must be fully clean)
swiftlint --strict --quiet
```

## Review Focus

1. **Settings written by the previous build** must still read back: the shelf location,
   Lynx icon, sections and hotkeys. A renamed `Defaults.Key` case whose raw value changed by
   accident would silently reset a setting. Task 3 Step 2 asserts every raw value after the
   rename.
2. **Module renamed to `Lynx_Bar` by default.** Dropping `PRODUCT_MODULE_NAME` would give the
   module `$(PRODUCT_NAME:c99extidentifier)` = `Lynx_Bar`, not `LynxBar`. The spec's "follows
   the target name" is wrong for this project, so set `PRODUCT_MODULE_NAME = LynxBar`
   explicitly. Checked in Task 1 Step 6.
3. **Over-matching replacements** inside raw strings or upstream references
   (`"EnableIceBar"`, `jordanbaird/Ice`). Word boundaries and the explicit tables prevent this.
   The permanent name check (Task 4) and the raw-value assertion (Task 3) catch it if not.
4. **Permissions and helper after the rename.** The designated requirement must stay
   `identifier "com.ikentrock.LynxBar" and certificate leaf = H"e0ed98…"`, so the installed
   app keeps its permissions and the helper still accepts it. Checked in Task 5.
5. **Stale derived data** making a broken project look fine. Every task builds into a freshly
   cleared `dd-lynx/Build`. Task 1 removes the whole `dd-lynx` folder first.

---

### Task 1: Rename the project, folder, scheme, target and module

**Files:**
- Move: `Ice/` → `LynxBar/`, `Ice.xcodeproj` → `LynxBar.xcodeproj`, `…/xcschemes/Ice.xcscheme` → `…/xcschemes/LynxBar.xcscheme`
- Modify: `LynxBar.xcodeproj/project.pbxproj`, both `.xcscheme` files, `.swiftlint.yml`, `Scripts/run-tests.sh`, `Resources/Artwork/render.swift`, `Config/Base.xcconfig` (comment), `README.md` (image path and build command), `CLAUDE.md` (commands and paths only)

**Interfaces:**
- Produces: `xcodebuild -project LynxBar.xcodeproj -scheme LynxBar` builds `Lynx Bar.app` with
  module `LynxBar`. All later tasks use this command.

- [ ] **Step 1: Start clean**

```sh
cd /Users/luisen-trifork/Documents/lynx-bar
git status --short            # expect: empty
git branch --show-current     # expect: lynx-bar-internal-rename
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx
```

- [ ] **Step 2: Confirm the new command fails before the change**

Run the build command from "Commands used throughout".
Expected: `xcodebuild: error: 'LynxBar.xcodeproj' does not exist.`

- [ ] **Step 3: Move the folder, project and scheme**

```sh
git mv Ice LynxBar
git mv Ice.xcodeproj LynxBar.xcodeproj
git mv LynxBar.xcodeproj/xcshareddata/xcschemes/Ice.xcscheme LynxBar.xcodeproj/xcshareddata/xcschemes/LynxBar.xcscheme
```

- [ ] **Step 4: Edit the project and schemes**

```sh
python3 - <<'EOF'
import re
p = 'LynxBar.xcodeproj/project.pbxproj'
s = open(p).read()
edits = [
    ('path = Ice; sourceTree = "<group>"; };', 'path = LynxBar; sourceTree = "<group>"; };', 1),
    ('/* Ice */', '/* LynxBar */', None),
    ('name = Ice;', 'name = LynxBar;', 1),
    ('productName = Ice;', 'productName = LynxBar;', 1),
    ('PBXNativeTarget "Ice"', 'PBXNativeTarget "LynxBar"', None),
    ('PBXProject "Ice"', 'PBXProject "LynxBar"', None),
    ('INFOPLIST_FILE = Ice/Resources/Info.plist;', 'INFOPLIST_FILE = LynxBar/Resources/Info.plist;', 2),
    ('PRODUCT_MODULE_NAME = Ice;', 'PRODUCT_MODULE_NAME = LynxBar;', 2),
    ('/* Ice.app */', '/* Lynx Bar.app */', None),
    ('path = Ice.app;', 'path = "Lynx Bar.app";', 1),
]
for old, new, count in edits:
    n = s.count(old)
    assert n > 0 and (count is None or n == count), (old, n)
    s = s.replace(old, new)
assert not re.search(r'\bIce\b', s), re.findall(r'.{30}\bIce\b.{30}', s)
open(p, 'w').write(s)
for sch in ['LynxBar', 'MenuBarItemService']:
    q = f'LynxBar.xcodeproj/xcshareddata/xcschemes/{sch}.xcscheme'
    t = open(q).read()
    t = t.replace('container:Ice.xcodeproj', 'container:LynxBar.xcodeproj')
    t = t.replace('BuildableName = "Ice.app"', 'BuildableName = "Lynx Bar.app"')
    t = t.replace('BlueprintName = "Ice"', 'BlueprintName = "LynxBar"')
    assert 'Ice' not in t, q
    open(q, 'w').write(t)
print('ok')
EOF
```

Expected: `ok`. The final assert proves no stray `Ice` remains in the project or schemes.

- [ ] **Step 5: Update paths that point into the old folder or project**

```sh
sed -i '' 's#^  - Ice$#  - LynxBar#' .swiftlint.yml
sed -i '' 's#\.\./Ice/Utilities/IceSettingsImporter\.swift#../LynxBar/Utilities/IceSettingsImporter.swift#' Scripts/run-tests.sh
sed -i '' 's#"Ice/Resources/Assets.xcassets"#"LynxBar/Resources/Assets.xcassets"#' Resources/Artwork/render.swift
sed -i '' 's#see Ice.xcodeproj build settings#see LynxBar.xcodeproj build settings#' Config/Base.xcconfig
sed -i '' 's#src="Ice/Resources/#src="LynxBar/Resources/#; s#-project Ice.xcodeproj -scheme Ice#-project LynxBar.xcodeproj -scheme LynxBar#' README.md
sed -i '' 's#-project Ice.xcodeproj -scheme Ice#-project LynxBar.xcodeproj -scheme LynxBar#; s#only lints `Ice/`#only lints `LynxBar/`#' CLAUDE.md
grep -n "^included" -A1 .swiftlint.yml
git grep -n "Ice/\|Ice\.xcodeproj\|scheme Ice" -- . ':!docs' ':!Packages'
```

Expected: `included:` followed by `  - LynxBar`, and the grep finds nothing.

- [ ] **Step 6: Build, test, lint, and check the module name**

Run the build, test and lint commands.
Expected:
- `** BUILD SUCCEEDED **`
- `PASS PeerCodeRequirement` and `PASS IceSettingsImporter` (three PASS lines in total)
- lint shows at most `LynxBar/Utilities/IconResource.swift`

Then:

```sh
APP=~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app"
ls ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Intermediates.noindex/LynxBar.build/Debug/LynxBar.build/Objects-normal/arm64/ | grep -m1 swiftmodule
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" -c "Print CFBundleExecutable" "$APP/Contents/Info.plist"
codesign -d -r- "$APP" 2>&1 | tail -1
```

Expected:
- a `LynxBar.swiftmodule` entry (not `Lynx_Bar` or `Ice`)
- `com.ikentrock.LynxBar` and `Lynx Bar`
- `designated => identifier "com.ikentrock.LynxBar" and certificate leaf = H"e0ed98f7b2d56951b4e0a99082debaf25af66311"`

If the intermediates path differs, find the module with
`find ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Intermediates.noindex -name "*.swiftmodule" -maxdepth 6 | head`.

- [ ] **Step 7: Commit**

```sh
git add -A LynxBar LynxBar.xcodeproj .swiftlint.yml Scripts/run-tests.sh Resources/Artwork/render.swift Config/Base.xcconfig README.md CLAUDE.md
git status --short | grep -v "^R\|^M\|^A\|^D" ; true   # expect: nothing unstaged or untracked
git commit -m "Rename the project, folder, scheme, target and module to LynxBar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Rename the types and their files

**Files:**
- Move:
  - `LynxBar/Main/IceApp.swift` → `LynxBar/Main/LynxBarApp.swift`
  - `LynxBar/MenuBar/IceBar/` → `LynxBar/MenuBar/LynxShelf/`, with `IceBar.swift` → `LynxShelf.swift`, `IceBarColorManager.swift` → `LynxShelfColorManager.swift`, `IceBarLocation.swift` → `LynxShelfLocation.swift`
  - `LynxBar/UI/IceUI/` → `LynxBar/UI/LynxUI/`, with `Ice*.swift` → `Lynx*.swift`
  - `LynxBar/UI/Utilities/IceColor.swift`, `IceGradient.swift` → `LynxColor.swift`, `LynxGradient.swift`
- Modify: every Swift file under `LynxBar/`, `Shared/`, `MenuBarItemService/` and `Scripts/` that uses a renamed type

**Interfaces:**
- Consumes: Task 1's build command.
- Produces: the type names of the spec's type table, e.g. `LynxShelfPanel`, `LynxSection`,
  `LynxWindowIdentifier`, `LynxBarApp`. `IceSettingsImporter` is unchanged.

- [ ] **Step 1: Count the old type names (the "failing" state)**

```sh
git grep -cP '\bIce(App|Bar(Panel|ColorManager|ContentView|HostingView|ItemView|ItemClickView|Location)|Color|Gradient(Picker(Root|Handle)?)?|Form(ToggleStyle|LabeledContentStyle)?|GroupBox|Menu|Picker|Slider|Section(Options|Layout|Divider)?|Window(Identifier)?)\b' -- LynxBar Shared MenuBarItemService Scripts | awk -F: '{s+=$2} END {print s}'
```

Expected: a positive count (about 210).

- [ ] **Step 2: Move the files and folders**

```sh
git mv LynxBar/Main/IceApp.swift LynxBar/Main/LynxBarApp.swift
git mv LynxBar/MenuBar/IceBar LynxBar/MenuBar/LynxShelf
git mv LynxBar/MenuBar/LynxShelf/IceBar.swift LynxBar/MenuBar/LynxShelf/LynxShelf.swift
git mv LynxBar/MenuBar/LynxShelf/IceBarColorManager.swift LynxBar/MenuBar/LynxShelf/LynxShelfColorManager.swift
git mv LynxBar/MenuBar/LynxShelf/IceBarLocation.swift LynxBar/MenuBar/LynxShelf/LynxShelfLocation.swift
git mv LynxBar/UI/IceUI LynxBar/UI/LynxUI
for f in LynxBar/UI/LynxUI/Ice*.swift LynxBar/UI/Utilities/IceColor.swift LynxBar/UI/Utilities/IceGradient.swift; do
  git mv "$f" "${f%/*}/Lynx${${f##*/}#Ice}"
done
git ls-files LynxBar | grep -E '/Ice[^/]*$'   # expect: only LynxBar/Utilities/IceSettingsImporter.swift
```

- [ ] **Step 3: Rename the types and fix the filename headers**

```sh
python3 - <<'EOF'
import re, subprocess
TYPES = {
  'IceApp': 'LynxBarApp',
  'IceBarPanel': 'LynxShelfPanel', 'IceBarColorManager': 'LynxShelfColorManager',
  'IceBarContentView': 'LynxShelfContentView', 'IceBarHostingView': 'LynxShelfHostingView',
  'IceBarItemView': 'LynxShelfItemView', 'IceBarItemClickView': 'LynxShelfItemClickView',
  'IceBarLocation': 'LynxShelfLocation',
  'IceColor': 'LynxColor', 'IceGradient': 'LynxGradient', 'IceGradientPicker': 'LynxGradientPicker',
  'IceGradientPickerRoot': 'LynxGradientPickerRoot', 'IceGradientPickerHandle': 'LynxGradientPickerHandle',
  'IceForm': 'LynxForm', 'IceFormToggleStyle': 'LynxFormToggleStyle',
  'IceFormLabeledContentStyle': 'LynxFormLabeledContentStyle',
  'IceGroupBox': 'LynxGroupBox', 'IceMenu': 'LynxMenu', 'IcePicker': 'LynxPicker', 'IceSlider': 'LynxSlider',
  'IceSection': 'LynxSection', 'IceSectionOptions': 'LynxSectionOptions',
  'IceSectionLayout': 'LynxSectionLayout', 'IceSectionDivider': 'LynxSectionDivider',
  'IceWindow': 'LynxWindow', 'IceWindowIdentifier': 'LynxWindowIdentifier',
}
FILES = {'IceApp.swift': 'LynxBarApp.swift', 'IceBar.swift': 'LynxShelf.swift',
         'IceBarColorManager.swift': 'LynxShelfColorManager.swift', 'IceBarLocation.swift': 'LynxShelfLocation.swift',
         'IceForm.swift': 'LynxForm.swift', 'IceGradientPicker.swift': 'LynxGradientPicker.swift',
         'IceGroupBox.swift': 'LynxGroupBox.swift', 'IceMenu.swift': 'LynxMenu.swift', 'IcePicker.swift': 'LynxPicker.swift',
         'IceSection.swift': 'LynxSection.swift', 'IceSlider.swift': 'LynxSlider.swift', 'IceWindow.swift': 'LynxWindow.swift',
         'IceColor.swift': 'LynxColor.swift', 'IceGradient.swift': 'LynxGradient.swift'}
pattern = re.compile(r'\b(' + '|'.join(sorted(TYPES, key=len, reverse=True)) + r')\b')
files = subprocess.run(['git', 'ls-files', '--', 'LynxBar/*.swift', 'Shared/*.swift', 'MenuBarItemService/*.swift', 'Scripts/*.swift'],
                       capture_output=True, text=True, check=True).stdout.split()
changed = 0
for f in files:
    s = open(f).read()
    t = pattern.sub(lambda m: TYPES[m.group(1)], s)
    lines = t.split('\n')
    if len(lines) > 1 and lines[1].startswith('//  ') and lines[1][4:] in FILES:
        lines[1] = '//  ' + FILES[lines[1][4:]]
    t = '\n'.join(lines)
    if t != s:
        open(f, 'w').write(t); changed += 1
print('files changed:', changed)
EOF
```

- [ ] **Step 4: Confirm no old type names remain**

Re-run Step 1's command. Expected: `0` (or no output).

- [ ] **Step 5: Build, test, lint**

Clear the old products with `rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build`, then run the
build, test and lint commands.
Expected: `BUILD SUCCEEDED`, three PASS lines, and lint showing at most `IconResource.swift`.
A `file_header` lint error means a header filename wasn't updated in Step 3: fix that file's
line 2.

- [ ] **Step 6: Commit**

```sh
git add -A LynxBar Shared MenuBarItemService Scripts
git commit -m "Rename Ice-prefixed types to Lynx and LynxShelf

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Rename the identifiers

**Files:**
- Modify: Swift files under `LynxBar/` (and `Shared/`, if any match) that use the identifiers in the spec's identifier table

**Interfaces:**
- Consumes: Task 2's type names (e.g. `LynxShelfLocation`).
- Produces:
  - **Settings, manager and shelf:** `shelfPanel` (on `MenuBarManager`), `useLynxShelf`,
    `lynxShelfLocation`, `lynxIcon`, `showLynxIcon`, `customLynxIconIsTemplate`,
    `lastCustomLynxIcon` (on `GeneralSettings`), `isLynxShelfPresented` (on
    `AppNavigationState`), `screenForLynxShelf`, `isMouseInsideLynxShelf`,
    `isMouseInsideLynxIcon`
  - **Enums and image sets:** `enableLynxShelf` (`HotkeyAction`), `LynxShelfLocation.lynxIcon`,
    `ControlItemImageSet.defaultLynxIcon`, `userSelectableLynxIcons`
  - **Layout constants:** `lynxFormDefaultPadding`, `lynxFormDefaultSpacing`,
    `lynxGroupBoxDefaultPadding`, `lynxSectionDefaultSpacing`
  - **Private helpers:** `lynxIconFrame`, `lynxIconMenuItem`, `lynxIconOptions`,
    `lynxIconPicker`, `lynxShelfLocationPicker`, `lynxShelfOptions`, `isImportingCustomLynxIcon`

- [ ] **Step 1: Record the raw values that must survive, then confirm the old names are present**

```sh
grep -nE 'case [a-zA-Z]+ = "[^"]*Ice[^"]*"' LynxBar/Utilities/Defaults.swift LynxBar/Hotkeys/HotkeyAction.swift LynxBar/MenuBar/ControlItem/ControlItem.swift | sed -E 's/.*= //' | sort > ~/Library/Caches/lynx-bar-dev/raw-values-before.txt
cat ~/Library/Caches/lynx-bar-dev/raw-values-before.txt
git grep -cP '\b(iceBarPanel|useIceBar|isIceBarPresented|screenForIceBar|isMouseInsideIceBar|enableIceBar|iceBarLocation|iceBarLocationPicker|iceBarOptions|iceIcon|showIceIcon|customIceIconIsTemplate|lastCustomIceIcon|defaultIceIcon|userSelectableIceIcons|isImportingCustomIceIcon|isMouseInsideIceIcon|iceIconFrame|iceIconMenuItem|iceIconOptions|iceIconPicker|iceFormDefaultPadding|iceFormDefaultSpacing|iceGroupBoxDefaultPadding|iceSectionDefaultSpacing)\b' -- LynxBar Shared | awk -F: '{s+=$2} END {print s}'
```

Expected: nine raw values:
- `"CustomIceIconIsTemplate"`, `"EnableIceBar"`, `"Ice.ControlItem.AlwaysHidden"`,
  `"Ice.ControlItem.Hidden"`, `"Ice.ControlItem.Visible"`, `"IceBarLocation"`, `"IceIcon"`,
  `"ShowIceIcon"`, `"UseIceBar"`
- each followed by its comma if the source has one; that's fine, it's compared verbatim in Step 3

The count should be positive (about 200).

- [ ] **Step 2: Rename the identifiers**

```sh
python3 - <<'EOF'
import re, subprocess
IDS = {
  'iceBarPanel': 'shelfPanel',
  'useIceBar': 'useLynxShelf', 'isIceBarPresented': 'isLynxShelfPresented', 'screenForIceBar': 'screenForLynxShelf',
  'isMouseInsideIceBar': 'isMouseInsideLynxShelf', 'enableIceBar': 'enableLynxShelf',
  'iceBarLocation': 'lynxShelfLocation', 'iceBarLocationPicker': 'lynxShelfLocationPicker', 'iceBarOptions': 'lynxShelfOptions',
  'iceIcon': 'lynxIcon', 'showIceIcon': 'showLynxIcon', 'customIceIconIsTemplate': 'customLynxIconIsTemplate',
  'lastCustomIceIcon': 'lastCustomLynxIcon', 'defaultIceIcon': 'defaultLynxIcon', 'userSelectableIceIcons': 'userSelectableLynxIcons',
  'isImportingCustomIceIcon': 'isImportingCustomLynxIcon', 'isMouseInsideIceIcon': 'isMouseInsideLynxIcon',
  'iceIconFrame': 'lynxIconFrame', 'iceIconMenuItem': 'lynxIconMenuItem', 'iceIconOptions': 'lynxIconOptions',
  'iceIconPicker': 'lynxIconPicker',
  'iceFormDefaultPadding': 'lynxFormDefaultPadding', 'iceFormDefaultSpacing': 'lynxFormDefaultSpacing',
  'iceGroupBoxDefaultPadding': 'lynxGroupBoxDefaultPadding', 'iceSectionDefaultSpacing': 'lynxSectionDefaultSpacing',
}
# Identifiers only: never inside string literals (raw values such as "IceBarLocation" are capitalised
# and wouldn't match anyway, but skip quoted text to be safe).
pattern = re.compile(r'"(?:[^"\\\n]|\\.)*"|\b(' + '|'.join(sorted(IDS, key=len, reverse=True)) + r')\b')
def sub(m):
    return IDS[m.group(1)] if m.group(1) else m.group(0)
files = subprocess.run(['git', 'ls-files', '--', 'LynxBar/*.swift', 'Shared/*.swift'], capture_output=True, text=True, check=True).stdout.split()
changed = 0
for f in files:
    s = open(f).read()
    t = pattern.sub(sub, s)
    if t != s:
        open(f, 'w').write(t); changed += 1
print('files changed:', changed)
EOF
```

- [ ] **Step 3: Confirm the old names are gone and the raw values are intact**

```sh
# Re-run Step 1's count command: expect 0 / no output.
grep -nE 'case [a-zA-Z]+ = "[^"]*Ice[^"]*"' LynxBar/Utilities/Defaults.swift LynxBar/Hotkeys/HotkeyAction.swift LynxBar/MenuBar/ControlItem/ControlItem.swift | sed -E 's/.*= //' | sort > ~/Library/Caches/lynx-bar-dev/raw-values-after.txt
diff ~/Library/Caches/lynx-bar-dev/raw-values-before.txt ~/Library/Caches/lynx-bar-dev/raw-values-after.txt && echo "raw values unchanged"
grep -nE 'case (showLynxIcon|lynxIcon|customLynxIconIsTemplate|useLynxShelf|lynxShelfLocation) = ' LynxBar/Utilities/Defaults.swift
grep -n 'case enableLynxShelf = "EnableIceBar"' LynxBar/Hotkeys/HotkeyAction.swift
```

Expected:
- `raw values unchanged`
- five `Defaults.Key` cases with their original raw values (e.g. `case showLynxIcon = "ShowIceIcon"`)
- the hotkey case line

- [ ] **Step 4: Build, test, lint**

Run `rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build`, then the build, test and lint commands.
Expected: `BUILD SUCCEEDED`, three PASS lines, and lint showing at most `IconResource.swift`.

- [ ] **Step 5: Commit**

```sh
git add -A LynxBar Shared
git commit -m "Rename ice-prefixed identifiers to lynx/shelf names

Stored keys keep their raw values (e.g. case showLynxIcon = \"ShowIceIcon\").

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Headers, text, the permanent name check, and the last lint fix

**Files:**
- Create: `Scripts/check-names.sh`
- Modify:
  - `Scripts/run-tests.sh` (runs the name check)
  - `.swiftlint.yml` (header rule)
  - `LynxBar/**/*.swift` (headers, comments, log text)
  - `LynxBar/Hotkeys/HotkeyRegistry.swift` (signature comment)
  - `LynxBar/Utilities/IconResource.swift` (lint)
  - `CLAUDE.md`

**Interfaces:**
- Produces: `Scripts/check-names.sh`. It exits 0 only when no code identifier outside the
  allowlist contains `Ice`/`ice`, and it prints the remaining prose mentions of "Ice" for
  review. `Scripts/run-tests.sh` runs it last.

- [ ] **Step 1: Write the name check (the failing test)**

`Scripts/check-names.sh`:

```sh
#!/bin/zsh
# Fails if Ice-derived code names remain outside the allowlist (see the Step 2 spec,
# docs/superpowers/specs/2026-10-02-lynx-bar-internal-rename-design.md, "What must not change").
# Also prints remaining prose mentions of "Ice" in Swift comments and strings for review.
cd "${0:A:h}/.."

ALLOW='"(ShowIceIcon|IceIcon|CustomIceIconIsTemplate|UseIceBar|IceBarLocation|EnableIceBar|Ice Cube)"|Ice\.ControlItem\.|IceSettingsImporter|com\.jordanbaird\.Ice|hasImportedIceSettings|legacyIceCube|jordanbaird/Ice'

# Code identifiers containing Ice/ice: IceFoo, fooIce, iceFoo.
hits=$(git grep -nP '\bIce[A-Z]\w*|\b[a-z]\w*Ice\w*|\bice[A-Z]\w*' -- 'LynxBar/*.swift' 'Shared/*.swift' 'MenuBarItemService/*.swift' 'Scripts/*' ':!Scripts/check-names.sh' \
    | grep -vP "$ALLOW")
# The header comment of every LynxBar file must say LynxBar.
headers=$(git grep -lx '//  Ice' -- 'LynxBar/*.swift')

if [[ -n $hits || -n $headers ]]; then
    [[ -n $hits ]] && { echo "Ice-derived names outside the allowlist:"; echo "$hits"; }
    [[ -n $headers ]] && { echo "Files with the old //  Ice header:"; echo "$headers"; }
    exit 1
fi

prose=$(git grep -nP '\bIce\b' -- 'LynxBar/*.swift' | grep -vP "$ALLOW|Based on Ice")
if [[ -n $prose ]]; then
    echo "Note: remaining mentions of Ice (expected only where they refer to upstream Ice):"
    echo "$prose"
fi
echo "PASS check-names"
```

Make it executable, and add it as the last step of `Scripts/run-tests.sh`, just before `exit $failed`:

```sh
../Scripts/check-names.sh || failed=1
```

(`run-tests.sh` runs from `Scripts/`, so this path resolves to the same script. `check-names.sh`
then `cd`s to the repo root itself.)

```sh
chmod +x Scripts/check-names.sh
Scripts/check-names.sh; echo "exit=$?"
```

Expected: `exit=1`, listing the 105 `//  Ice` headers (all identifiers are already renamed).

- [ ] **Step 2: Update headers and the lint rule**

```sh
python3 - <<'EOF'
import subprocess
files = subprocess.run(['git', 'ls-files', '--', 'LynxBar/*.swift'], capture_output=True, text=True, check=True).stdout.split()
n = 0
for f in files:
    lines = open(f).read().split('\n')
    if len(lines) > 2 and lines[0] == '//' and lines[2] == '//  Ice':
        lines[2] = '//  LynxBar'
        open(f, 'w').write('\n'.join(lines)); n += 1
print('headers updated:', n)
EOF
python3 - <<'EOF'
p = '.swiftlint.yml'; s = open(p).read()
old = '    //  SWIFTLINT_CURRENT_FILENAME\n    //  Ice\n    //'
assert s.count(old) == 1
open(p, 'w').write(s.replace(old, '    //  SWIFTLINT_CURRENT_FILENAME\n    //  LynxBar\n    //'))
print('lint rule updated')
EOF
```

Expected: `headers updated:` followed by a number equal to the count of LynxBar Swift files
with the old header (about 105), then `lint rule updated`.

- [ ] **Step 3: Update comments and log text that describe this app**

```sh
python3 - <<'EOF'
import re, subprocess
PHRASES = [  # (pattern, replacement), applied in order
    (r'\bthe Ice Bar\b', 'the Lynx Shelf'), (r'\bThe Ice Bar\b', 'The Lynx Shelf'), (r'\bIce Bar\b', 'Lynx Shelf'),
    (r'\bthe Ice icon\b', 'the Lynx icon'), (r'\bThe Ice icon\b', 'The Lynx icon'), (r'\bIce icon\b', 'Lynx icon'),
    (r"\bIce's\b", "Lynx Bar's"), (r'\bIce’s\b', 'Lynx Bar’s'),
]
KEEP = re.compile(r'Ice Cube|jordanbaird|Based on Ice|based on Ice|IceSettingsImporter|upstream|"Ice\.ControlItem|legacyIceCube|Ice stored')
files = subprocess.run(['git', 'ls-files', '--', 'LynxBar/*.swift'], capture_output=True, text=True, check=True).stdout.split()
n = 0
for f in files:
    out = []
    for line in open(f).read().split('\n'):
        if not KEEP.search(line):
            for pat, rep in PHRASES:
                line = re.sub(pat, rep, line)
        out.append(line)
    t = '\n'.join(out)
    if t != open(f).read():
        open(f, 'w').write(t); n += 1
print('files updated:', n)
EOF
git grep -nP '\bIce\b' -- 'LynxBar/*.swift' | grep -vP 'Ice Cube|jordanbaird|Based on Ice|IceSettingsImporter|"Ice\.ControlItem|legacyIceCube' 
```

Review every remaining line the grep prints. For each one:
- **About this app** (e.g. "Ice's control items", "Make sure Ice …", "the "Ice" process"): change
  "Ice" to "Lynx Bar" by hand.
- **About upstream Ice, or Ice's stored data** (e.g. the importer's doc comments, "The name
  Ice stored …"): keep it.

In `LynxBar/Hotkeys/HotkeyRegistry.swift`, change the comment
`// OSType for Ice` to `// Carbon hotkey signature ('Ice ', inherited from upstream; in-process only, never persisted)`.

- [ ] **Step 4: Fix the last lint violation**

In `LynxBar/Utilities/IconResource.swift`, replace `.aspectRatio(contentMode: .fit)` with
`.scaledToFit()`. If the violation is `.fill`, use `.scaledToFill()`.

- [ ] **Step 5: Update `CLAUDE.md` for the new names**

Apply these edits in `CLAUDE.md`:
- **Project** paragraph: replace the sentence "The Xcode target, scheme and Swift module are
  still named `Ice`, as are most type names (`IceBar` is the "Lynx Shelf") and the `//  Ice`
  file headers — an internal rename is planned separately." with "The Xcode project is
  `LynxBar.xcodeproj` with the `LynxBar` scheme, target and Swift module. Sources live in
  `LynxBar/`, and file headers read `//  LynxBar`. Some names still mention Ice on purpose:
  stored defaults keys and raw values, `IceSettingsImporter`, and references to upstream."
- **Commands:** "one app scheme (`Ice`)" becomes "one app scheme (`LynxBar`)".
- **Lint conventions:** the header becomes `//\n//  <FileName>.swift\n//  LynxBar\n//`.
- **Architecture:**
  - `Main/IceApp.swift` becomes `Main/LynxBarApp.swift`.
  - "`MenuBar/IceBar/`, a panel below the menu bar" becomes "`MenuBar/LynxShelf/`
    (`LynxShelfPanel`), a panel below the menu bar".
- Under **Commands**, add: `Scripts/check-names.sh` (also run by `run-tests.sh`) fails if
  Ice-derived names creep back in outside the allowlist.

Check: `grep -n "IceBar\|IceApp\|scheme (\`Ice\`)\|//  Ice" CLAUDE.md` should print nothing.

- [ ] **Step 6: Run the check, tests, lint and build**

```sh
Scripts/check-names.sh; echo "exit=$?"
```

Expected: `PASS check-names` and `exit=0`. The "Note:" list may show lines about upstream Ice;
each must be one you decided to keep in Step 3.

Then run `rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build` and the build, test and lint
commands.
Expected:
- `BUILD SUCCEEDED`
- `PASS PeerCodeRequirement`, `PASS IceSettingsImporter` and `PASS check-names` in both test runs
- `swiftlint --strict --quiet` prints **nothing**

- [ ] **Step 7: Commit**

```sh
git add -A LynxBar Scripts .swiftlint.yml CLAUDE.md
git commit -m "Use LynxBar headers and wording; guard against Ice names returning

Headers now read //  LynxBar, comments and log text use Lynx vocabulary,
and Scripts/check-names.sh (run by run-tests.sh) fails if Ice-derived names
appear outside the allowlist. Also fixes the last SwiftLint violation.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Verify behavior is unchanged and hand off

**Files:** none (fixes found here go back to the owning task's files as new commits).

- [ ] **Step 1: Release build and identity**

```sh
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build
xcodebuild -project LynxBar.xcodeproj -scheme LynxBar -configuration Release \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build > ~/Library/Caches/lynx-bar-dev/release.log 2>&1
grep -E "error:|\*\* BUILD" ~/Library/Caches/lynx-bar-dev/release.log | sort -u
R=~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Release/"Lynx Bar.app"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" -c "Print CFBundleExecutable" -c "Print CFBundleShortVersionString" "$R/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$R/Contents/XPCServices/MenuBarItemService.xpc/Contents/Info.plist"
codesign -d -r- "$R" 2>&1 | tail -1
codesign -d -r- "$R/Contents/XPCServices/MenuBarItemService.xpc" 2>&1 | tail -1
```

Expected:
- `BUILD SUCCEEDED`
- `com.ikentrock.LynxBar`, `Lynx Bar`, `0.12.0`
- `com.ikentrock.LynxBar.MenuBarItemService`
- both designated requirements exactly as before:
  `identifier "com.ikentrock.LynxBar" and certificate leaf = H"e0ed98f7b2d56951b4e0a99082debaf25af66311"`,
  and the same for `….MenuBarItemService`

- [ ] **Step 2: Install over the current app, without resetting anything**

```sh
pkill -x "Lynx Bar"; sleep 1
defaults read com.ikentrock.LynxBar IceBarLocation; defaults read com.ikentrock.LynxBar UseIceBar
rm -rf ~/Applications/"Lynx Bar.app"; cp -R "$R" ~/Applications/
open ~/Applications/"Lynx Bar.app"; sleep 8
/usr/bin/log show --last 20s --info --debug --style compact --predicate 'subsystem == "com.ikentrock.LynxBar" AND (eventMessage CONTAINS[c] "permissions" OR eventMessage CONTAINS[c] "helper" OR eventMessage CONTAINS "Error decoding")' | tail -5
pgrep -fl MenuBarItemService | head -1
defaults read com.ikentrock.LynxBar IceBarLocation; defaults read com.ikentrock.LynxBar UseIceBar
```

Expected:
- `Stopping all permissions checks` (setup ran, so the permissions were kept)
- no "helper unavailable" and no "Error decoding"
- the helper process is running
- the two settings read the same before and after

**Owner check:**
- no permission prompt
- the Lynx icon is in place
- the Lynx Shelf shows hidden items
- Settings → General shows the same shelf location and Lynx icon
- About shows 0.12.0

- [ ] **Step 3: Hand off**

Use superpowers:finishing-a-development-branch to integrate `lynx-bar-internal-rename` into
`main`. The owner has said they want this work pushed to `main` on `origin`
(`ikentrock/lynx-bar`), but confirm the menu choice first.
