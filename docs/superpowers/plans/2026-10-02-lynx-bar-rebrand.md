# Lynx Bar Rebrand (Step 1) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn this fork into its own app, Lynx Bar, built on upstream's `macos-26` branch.
It should build with Xcode 27, sign without an Apple team, trust only its own helper, never
update from Ice, import Ice's settings once, and say "Lynx Bar" everywhere users look.

**Architecture:** Merge `upstream/macos-26` (which owns menu bar item identity on macOS 26 via
the `MenuBarItemService` XPC helper). Then:
- Vendor CompactSlider so the project compiles.
- Move signing and identity into `Config/Base.xcconfig`.
- Replace the helper's "same team" XPC check with "same certificate + expected identifier",
  using the C XPC API.
- Add a one-shot Ice settings importer, turn Sparkle off when no feed is configured, and
  rebrand strings, artwork and docs.

Internal names (`Ice` target, `IceBar` types, `//  Ice` headers) are untouched; that is Step 2.

**Tech Stack:** Swift 5 mode, SwiftUI + AppKit, Xcode 27 / macOS 26 SDK (deployment target
macOS 14), XPC C API, Security framework, Sparkle, SwiftLint.

**Spec:** `docs/superpowers/specs/2026-10-02-lynx-bar-rebrand-design.md`. Read it before
starting; it holds the reasons behind every decision here.

## Global Constraints

- App name: `Lynx Bar`. Bundle ID: `com.ikentrock.LynxBar`. Helper bundle ID:
  `com.ikentrock.LynxBar.MenuBarItemService`.
- Version `0.12.0`. `CURRENT_PROJECT_VERSION` stays upstream's value.
- Copyright string: `© Luisen Ramos. Based on Ice by Jordan Baird.`
- Feature names: "Ice Bar" → **"Lynx Shelf"**, "Ice icon" → **"Lynx icon"**.
- Stored defaults keys never change (`IceIcon`, `UseIceBar`, `Ice.ControlItem.*`, …).
- Swift module name stays `Ice` (`PRODUCT_MODULE_NAME = Ice`).
- No `DEVELOPMENT_TEAM` anywhere. Default signing is ad-hoc (`-`). A gitignored
  `Config/Local.xcconfig` may set `CODE_SIGN_IDENTITY = Luisen`.
- The helper connection is refused, never left unchecked, when a process has no certificate.
- Deployment target stays macOS 14.0. Don't add a test target (tests are standalone `swiftc`
  scripts under `Scripts/Tests`).
- Every Swift file under `Ice/` starts with `//\n//  <FileName>.swift\n//  Ice\n//`. Files
  under `Shared/` and `MenuBarItemService/` use their folder name in place of `Ice`, as
  upstream does.
- `swiftlint --strict` must report nothing for files this plan touches (SwiftLint only lints
  `Ice/`).
- Never commit `Config/Local.xcconfig`, personal settings exports, or anything from
  `~/Library/Caches/lynx-bar-dev`.
- Commit author: this is a personal repo, so the existing `luisenramos@gmail.com` identity is
  correct. End every commit message with
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Shell pitfall:** in zsh, `log` is a builtin. Always call `/usr/bin/log`.

## Build & check commands (used throughout)

```sh
# Ad-hoc build (no Local.xcconfig needed)
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build 2>&1 | tail -3

# Lint (CI runs exactly this)
swiftlint --strict

# Script tests (from Task 3 on)
Scripts/run-tests.sh
```

The built app is at `~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/Lynx Bar.app`
(before Task 2: `…/Debug/Ice.app`).

## Review Focus

1. **Existing users' saved icon.** Someone who picked "Ice Cube" in Ice has
   `{"name":"Ice Cube","hidden":{"catalog":"IceCubeStroke"},…}` stored. After the import it
   must decode to the Lynx set and render, not fail to decode or point at a deleted asset. The
   legacy-decoding test is in Task 7, Step 6.
2. **Mismatched or refused helper.** With a refused helper, the Lynx Shelf, Layout pane and
   search show the helper message instead of a spinner that never ends. The item manager also
   never caches or moves items. A spike build moved a real item. Checked in Task 4, Steps 9–11.
3. **Importer with partial or odd data.** If Ice's domain is absent, empty, or shares keys
   with Lynx Bar, existing Lynx Bar values are never overwritten and the flag is still set.
   Tests are in Task 6, Step 1.
4. **Odd bundle identifiers and signatures.** A process with no bundle ID, an identifier
   containing quotes, or ad-hoc signing yields no requirement and a refused connection. It
   must not produce a malformed requirement string that XPC rejects at runtime. Tests are in
   Task 3, Step 1.
5. **Update paths that bypass the About pane.** The menu bar menu's "Check for Updates…" and
   the update notification handler must not start Sparkle when no feed is configured.
   Checked in Task 5, Step 4.

---

### Task 1: Merge the macOS 26 base and vendor CompactSlider

**Files:**
- Merge: `upstream/macos-26` into branch `lynx-bar-rebrand`
- Create: `Packages/CompactSlider/` (from upstream CompactSlider 1.2.1), `Packages/CompactSlider/VENDORED.md`
- Modify: `Packages/CompactSlider/Sources/CompactSlider/ProminentCompactSliderStyle.swift`, `Ice.xcodeproj/project.pbxproj`, `Ice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

**Interfaces:**
- Produces: a tree that builds ad-hoc with Xcode 27; product `Ice.app` with the helper at
  `Contents/XPCServices/MenuBarItemService.xpc`.

- [ ] **Step 1: Confirm the starting point**

```sh
cd /Users/luisen-trifork/Documents/lynx-bar
git status --short          # expect: empty
git branch --show-current   # expect: lynx-bar-rebrand
git fetch upstream
```

- [ ] **Step 2: Merge upstream's macOS 26 branch**

```sh
git merge --no-ff upstream/macos-26 -m "Merge upstream macos-26 as the Lynx Bar base

Upstream's unreleased macOS 26 rework identifies menu bar items through the
MenuBarItemService helper, which 0.11.12 cannot do on macOS 26 (item windows
are owned by Control Center). See docs/superpowers/specs/2026-10-02-lynx-bar-rebrand-design.md.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected: the merge completes without conflicts (a trial merge on 2026-10-02 was clean).

- [ ] **Step 3: Confirm the build fails as expected**

```sh
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build 2>&1 | grep -E "error:|BUILD" | sort -u
```

Expected: `ProminentCompactSliderStyle.swift:37:18: error: ambiguous use of 'opacity'` and `** BUILD FAILED **`.

- [ ] **Step 4: Vendor CompactSlider 1.2.1 at the pinned revision**

```sh
rm -rf /tmp/cs && git clone -q https://github.com/buh/CompactSlider.git /tmp/cs
git -C /tmp/cs checkout -q e5219ff353613b6493bfe5a3333c3bfa2d1e4d57
mkdir -p Packages/CompactSlider
cp -R /tmp/cs/Package.swift /tmp/cs/Sources /tmp/cs/LICENSE /tmp/cs/README.md Packages/CompactSlider/
rm -rf /tmp/cs
grep -n "LinearGradient(" -A6 Packages/CompactSlider/Sources/CompactSlider/ProminentCompactSliderStyle.swift
```

Expected: the grep shows the `.background(LinearGradient(...).opacity(...))` block around line 32–37.

- [ ] **Step 5: Patch the ambiguous `opacity` call**

In `Packages/CompactSlider/Sources/CompactSlider/ProminentCompactSliderStyle.swift`, replace:

```swift
            .background(
                LinearGradient(
                    colors: [lowerColor, upperColor],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .opacity(
```

with:

```swift
            .background(
                // Patched for Lynx Bar: wrapping the gradient in a shape avoids the
                // `View.opacity` / `ShapeStyle.opacity` ambiguity in the Xcode 27 SDK.
                Rectangle().fill(LinearGradient(
                    colors: [lowerColor, upperColor],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .opacity(
```

If 1.2.1's code differs from that snippet, apply the same change (wrap the `LinearGradient`
that `.opacity` is called on in `Rectangle().fill(...)`) and record the actual lines in
`VENDORED.md`.

- [ ] **Step 6: Write `Packages/CompactSlider/VENDORED.md`**

```markdown
# Vendored CompactSlider

This is [CompactSlider](https://github.com/buh/CompactSlider) 1.2.1
(revision `e5219ff353613b6493bfe5a3333c3bfa2d1e4d57`), MIT-licensed (see `LICENSE`),
copied here as a local Swift package.

It is vendored because no 1.x release compiles with the Xcode 27 SDK: the gradient
background in `ProminentCompactSliderStyle.swift` hits an ambiguous `opacity` call
(`View.opacity` vs `ShapeStyle.opacity`). 2.x compiles, but has a different API.

Local changes:

- `Sources/CompactSlider/ProminentCompactSliderStyle.swift`: the gradient background is
  wrapped in `Rectangle().fill(...)` so `opacity` resolves to `View.opacity`.

Only `Package.swift`, `Sources/`, `LICENSE` and `README.md` were copied.
```

- [ ] **Step 7: Point the project at the local package**

```sh
python3 - <<'EOF'
import json
p = 'Ice.xcodeproj/project.pbxproj'
s = open(p).read()
ID = '17F71BB32B880B4500905CBA'
old_ref = f'''		{ID} /* XCRemoteSwiftPackageReference "CompactSlider" */ = {{
			isa = XCRemoteSwiftPackageReference;
			repositoryURL = "https://github.com/buh/CompactSlider";
			requirement = {{
				kind = upToNextMajorVersion;
				minimumVersion = 1.1.5;
			}};
		}};
'''
assert old_ref in s, "remote CompactSlider reference not found"
s = s.replace(old_ref, '')
local = f'''/* Begin XCLocalSwiftPackageReference section */
		{ID} /* XCLocalSwiftPackageReference "Packages/CompactSlider" */ = {{
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/CompactSlider;
		}};
/* End XCLocalSwiftPackageReference section */

/* Begin XCRemoteSwiftPackageReference section */'''
assert s.count('/* Begin XCRemoteSwiftPackageReference section */') == 1
s = s.replace('/* Begin XCRemoteSwiftPackageReference section */', local)
s = s.replace(f'{ID} /* XCRemoteSwiftPackageReference "CompactSlider" */',
              f'{ID} /* XCLocalSwiftPackageReference "Packages/CompactSlider" */')
open(p, 'w').write(s)
r = 'Ice.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
d = json.load(open(r))
d['pins'] = [x for x in d['pins'] if x['identity'] != 'compactslider']
open(r, 'w').write(json.dumps(d, indent=2, separators=(',', ' : ')) + '\n')
print("ok")
EOF
grep -c "CompactSlider" Ice.xcodeproj/project.pbxproj   # expect: 6
```

- [ ] **Step 8: Build from clean derived data**

```sh
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx \
  CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build 2>&1 | grep -E "error:|BUILD" | sort -u
ls ~/Library/Caches/lynx-bar-dev/dd-lynx/SourcePackages/checkouts
```

Expected: `** BUILD SUCCEEDED **`, and `CompactSlider` is **not** listed among the checkouts.

- [ ] **Step 9: Commit**

```sh
git add Packages Ice.xcodeproj
git commit -m "Vendor CompactSlider 1.2.1 to build with Xcode 27

No CompactSlider 1.x release compiles with the Xcode 27 SDK (ambiguous
View/ShapeStyle opacity). Vendor the pinned 1.2.1 revision as a local package
with a one-line patch. See Packages/CompactSlider/VENDORED.md.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Identity and signing via xcconfig

**Files:**
- Create: `Config/Base.xcconfig`, `Config/Local.xcconfig.example`
- Modify: `Ice.xcodeproj/project.pbxproj`, `.gitignore`

**Interfaces:**
- Consumes: Task 1's buildable tree.
- Produces: the app product `Lynx Bar.app` (bundle ID `com.ikentrock.LynxBar`, version
  0.12.0, module `Ice`) embedding `MenuBarItemService.xpc` (bundle ID
  `com.ikentrock.LynxBar.MenuBarItemService`). Both are ad-hoc signed by default and
  certificate-signed when `Config/Local.xcconfig` exists.

- [ ] **Step 1: Create `Config/Base.xcconfig`**

```
// Base.xcconfig
// Shared build settings for Lynx Bar. Applied at project level; targets may
// not override the settings below (see Ice.xcodeproj build settings).

// The app's bundle identifier. The helper's is derived from it.
LYNX_BUNDLE_ID = com.ikentrock.LynxBar

MARKETING_VERSION = 0.12.0
INFOPLIST_KEY_NSHumanReadableCopyright = © Luisen Ramos. Based on Ice by Jordan Baird.

// Lynx Bar is not built with an Apple Developer team. By default builds are
// ad-hoc signed; the helper connection then refuses to start (see README).
// To sign with a certificate, copy Local.xcconfig.example to Local.xcconfig.
DEVELOPMENT_TEAM =
CODE_SIGN_STYLE = Manual
CODE_SIGN_IDENTITY = -

#include? "Local.xcconfig"
```

- [ ] **Step 2: Create `Config/Local.xcconfig.example`**

```
// Local.xcconfig
// Copy this file to Config/Local.xcconfig (gitignored) and set the name of a
// code-signing certificate from your login keychain. A self-signed certificate
// works: Keychain Access → Certificate Assistant → Create a Certificate…,
// Identity Type "Self Signed Root", Certificate Type "Code Signing".
CODE_SIGN_IDENTITY = Your Certificate Name
```

- [ ] **Step 3: Ignore the local file and create yours**

Append to `.gitignore`:

```
Config/Local.xcconfig
```

Then:

```sh
printf 'CODE_SIGN_IDENTITY = Luisen\n' > Config/Local.xcconfig
git check-ignore Config/Local.xcconfig   # expect: Config/Local.xcconfig
```

- [ ] **Step 4: Wire the xcconfig into the project and remove the conflicting target settings**

```sh
python3 - <<'EOF'
import re
p = 'Ice.xcodeproj/project.pbxproj'
s = open(p).read()
FREF = '4C59BA5E2E8E100000000001'
# 1. File reference for Config/Base.xcconfig
s = s.replace('/* Begin PBXFileReference section */',
  '/* Begin PBXFileReference section */\n\t\t' + FREF +
  ' /* Base.xcconfig */ = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; name = Base.xcconfig; path = Config/Base.xcconfig; sourceTree = "<group>"; };', 1)
# 2. Show it in the main group
main = '\t\t716683212A767E6A006ABF84 = {\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n'
assert main in s
s = s.replace(main, main + '\t\t\t\t' + FREF + ' /* Base.xcconfig */,\n', 1)
# 3. Project-level configs: base on the xcconfig, drop team and copyright
for cfg in ['716683372A767E6B006ABF84 /* Debug */', '716683382A767E6B006ABF84 /* Release */']:
    head = '\t\t' + cfg + ' = {\n\t\t\tisa = XCBuildConfiguration;\n'
    assert head in s, cfg
    s = s.replace(head, head + '\t\t\tbaseConfigurationReference = ' + FREF + ' /* Base.xcconfig */;\n', 1)
s = re.sub(r'\n\t\t\t\tDEVELOPMENT_TEAM = K2ATHQPJDP;', '', s)
s = re.sub(r'\n\t\t\t\tINFOPLIST_KEY_NSHumanReadableCopyright = "[^"]*";', '', s)
# 4. Targets: no signing/version overrides; derived names and IDs
s = s.replace('\n\t\t\t\t"CODE_SIGN_IDENTITY[sdk=macosx*]" = "Apple Development";', '')
s = s.replace('\n\t\t\t\tCODE_SIGN_STYLE = Automatic;', '')
s = s.replace('\n\t\t\t\tMARKETING_VERSION = "0.11.13-dev.2a";', '')
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice;',
  'PRODUCT_BUNDLE_IDENTIFIER = "$(LYNX_BUNDLE_ID)";\n\t\t\t\tPRODUCT_MODULE_NAME = Ice;')
s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.jordanbaird.Ice.MenuBarItemService;',
  'PRODUCT_BUNDLE_IDENTIFIER = "$(LYNX_BUNDLE_ID).MenuBarItemService";')
# App target only: product name (its configs carry INFOPLIST_FILE = Ice/Resources/Info.plist)
s = re.sub(r'(INFOPLIST_FILE = Ice/Resources/Info\.plist;(?:(?!name = ).)*?)PRODUCT_NAME = "\$\(TARGET_NAME\)";',
           r'\1PRODUCT_NAME = "Lynx Bar";', s, flags=re.S)
open(p, 'w').write(s)
EOF
grep -nE "DEVELOPMENT_TEAM|CODE_SIGN_STYLE|CODE_SIGN_IDENTITY|PRODUCT_BUNDLE_IDENTIFIER|PRODUCT_NAME|PRODUCT_MODULE_NAME|MARKETING_VERSION|baseConfigurationReference|Copyright" Ice.xcodeproj/project.pbxproj
```

Expected output:
- 2× `baseConfigurationReference`
- 2× `PRODUCT_BUNDLE_IDENTIFIER = "$(LYNX_BUNDLE_ID)";` and 2× `… "$(LYNX_BUNDLE_ID).MenuBarItemService";`
- 2× `PRODUCT_MODULE_NAME = Ice;`
- 2× `PRODUCT_NAME = "Lynx Bar";` and 2× `PRODUCT_NAME = "$(TARGET_NAME)";` (the helper)
- **no** `DEVELOPMENT_TEAM`, `CODE_SIGN_STYLE`, `CODE_SIGN_IDENTITY`, `MARKETING_VERSION` or copyright lines

- [ ] **Step 5: Ad-hoc build (move `Local.xcconfig` aside temporarily)**

```sh
mv Config/Local.xcconfig /tmp/Local.xcconfig.bak
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build 2>&1 | grep -E "error:|BUILD" | sort -u
APP=~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" -c "Print CFBundleShortVersionString" -c "Print NSHumanReadableCopyright" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" "$APP/Contents/XPCServices/MenuBarItemService.xpc/Contents/Info.plist"
codesign -dv "$APP" 2>&1 | grep -E "Signature|TeamIdentifier"
mv /tmp/Local.xcconfig.bak Config/Local.xcconfig
```

Expected:
- `BUILD SUCCEEDED`
- `com.ikentrock.LynxBar`, `0.12.0`, `© Luisen Ramos. Based on Ice by Jordan Baird.`
- `com.ikentrock.LynxBar.MenuBarItemService`
- `Signature=adhoc`, `TeamIdentifier=not set`

- [ ] **Step 6: Certificate build**

```sh
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx/Build
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build 2>&1 | grep -E "error:|BUILD" | sort -u
APP=~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app"
codesign -d -r- "$APP" 2>&1 | tail -1
codesign -d -r- "$APP/Contents/XPCServices/MenuBarItemService.xpc" 2>&1 | tail -1
```

Expected:
- `designated => identifier "com.ikentrock.LynxBar" and certificate leaf = H"e0ed98f7b2d56951b4e0a99082debaf25af66311"`
- the same for `com.ikentrock.LynxBar.MenuBarItemService`

If the certificate can't be found, check `security find-identity -p codesigning` for the
name. A `CSSMERR_TP_NOT_TRUSTED` status is fine: this was verified on 2026-10-02.

- [ ] **Step 7: Commit**

```sh
git add Config/Base.xcconfig Config/Local.xcconfig.example .gitignore Ice.xcodeproj/project.pbxproj
git status --short   # Config/Local.xcconfig must NOT appear
git commit -m "Give Lynx Bar its own identity and signing config

Bundle IDs derive from LYNX_BUNDLE_ID in Config/Base.xcconfig; the app is
'Lynx Bar' 0.12.0 with module name Ice kept until the internal rename. No
Apple team: builds are ad-hoc unless a gitignored Config/Local.xcconfig names
a signing certificate.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Script test harness, helper identity and peer requirement

**Files:**
- Create: `Scripts/run-tests.sh`, `Scripts/Tests/Support/Expect.swift`, `Scripts/Tests/PeerCodeRequirement/main.swift`, `Shared/Services/MenuBarItemServiceIdentity.swift`, `Shared/Services/PeerCodeRequirement.swift`

**Interfaces:**
- Produces:
  - `enum MenuBarItemServiceIdentity`:
    - `static let serviceSuffix: String` (value `".MenuBarItemService"`)
    - `static func serviceName(forHostIdentifier host: String) -> String`
    - `static func hostIdentifier(forServiceIdentifier service: String) -> String?`
  - `enum PeerCodeRequirement`:
    - `enum Signer: Equatable, CustomStringConvertible { case team(String); case certificate(sha1: String) }`
    - `static func currentSigner() -> Signer?`
    - `static func requirement(for signer: Signer?, peerIdentifier: String) -> String?`
    - `static func requirement(forPeerIdentifier identifier: String) -> String?` (uses `currentSigner()`)
  - `Scripts/run-tests.sh`: compiles and runs every script test. It exits non-zero on any
    failure. If env `LYNX_TEST_CERT` is set to a certificate SHA-1, it also re-runs the
    signer test with the binary signed by that certificate.

- [ ] **Step 1: Write the failing test**

`Scripts/Tests/Support/Expect.swift`:

```swift
//
//  Expect.swift
//  Tests
//

import Foundation

/// The number of failed expectations so far.
nonisolated(unsafe) var expectationFailures = 0

/// Records a failure if the condition is false.
func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if !condition() {
        expectationFailures += 1
        print("FAIL (line \(line)): \(message)")
    }
}

/// Prints a summary and exits with a non-zero status if anything failed.
func finishTests(_ name: String) -> Never {
    if expectationFailures == 0 {
        print("PASS \(name)")
        exit(0)
    }
    print("\(expectationFailures) failure(s) in \(name)")
    exit(1)
}
```

`Scripts/Tests/PeerCodeRequirement/main.swift`:

```swift
//
//  main.swift
//  Tests
//

import Foundation

// MARK: Helper identity

expect(
    MenuBarItemServiceIdentity.serviceName(forHostIdentifier: "com.ikentrock.LynxBar")
        == "com.ikentrock.LynxBar.MenuBarItemService",
    "service name is the host identifier plus the suffix"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: "com.ikentrock.LynxBar.MenuBarItemService")
        == "com.ikentrock.LynxBar",
    "host identifier strips the suffix"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: "com.ikentrock.LynxBar") == nil,
    "an identifier without the suffix has no host"
)
expect(
    MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: ".MenuBarItemService") == nil,
    "the bare suffix has no host"
)

// MARK: Requirement strings

expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: "com.example.App")
        == #"anchor apple generic and certificate leaf[subject.OU] = "ABCDE12345" and identifier "com.example.App""#,
    "team signer requires same team and identifier"
)
expect(
    PeerCodeRequirement.requirement(
        for: .certificate(sha1: "e0ed98f7b2d56951b4e0a99082debaf25af66311"),
        peerIdentifier: "com.example.App"
    ) == #"certificate leaf = H"e0ed98f7b2d56951b4e0a99082debaf25af66311" and identifier "com.example.App""#,
    "certificate signer requires same leaf certificate and identifier"
)
expect(
    PeerCodeRequirement.requirement(for: nil, peerIdentifier: "com.example.App") == nil,
    "no signer means no requirement"
)
expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: #"x" or anchor apple"#) == nil,
    "identifiers with quotes or spaces are rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .team("ABCDE12345"), peerIdentifier: "") == nil,
    "an empty identifier is rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .certificate(sha1: "not-hex"), peerIdentifier: "com.example.App") == nil,
    "a malformed certificate hash is rejected"
)
expect(
    PeerCodeRequirement.requirement(for: .team(#"AB"CD"#), peerIdentifier: "com.example.App") == nil,
    "a malformed team identifier is rejected"
)

// MARK: Current process signature

let signer = PeerCodeRequirement.currentSigner()
if let expectedSHA1 = ProcessInfo.processInfo.environment["EXPECT_CERT_SHA1"] {
    expect(
        signer == .certificate(sha1: expectedSHA1.lowercased()),
        "certificate-signed binary reports its leaf certificate (got \(String(describing: signer)))"
    )
} else {
    expect(signer == nil, "ad-hoc/linker-signed binary has no signer (got \(String(describing: signer)))")
}

finishTests("PeerCodeRequirement")
```

`Scripts/run-tests.sh`:

```sh
#!/bin/zsh
# Compiles and runs Lynx Bar's standalone script tests.
#
# Each test is Scripts/Tests/<Name>/main.swift, compiled together with
# Scripts/Tests/Support/*.swift and the app sources listed below.
# Set LYNX_TEST_CERT to a code-signing certificate's SHA-1 to also test
# certificate signing (e.g. from `security find-identity -p codesigning`).
set -euo pipefail
cd "${0:A:h}/.."
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
failed=0

build() { # name, sources...
    local name=$1; shift
    swiftc -swift-version 5 -o "$OUT/$name" Tests/Support/*.swift "Tests/$name/main.swift" "$@"
}

run() { # name
    "$OUT/$1" || failed=1
}

build PeerCodeRequirement ../Shared/Services/MenuBarItemServiceIdentity.swift ../Shared/Services/PeerCodeRequirement.swift
run PeerCodeRequirement
if [[ -n ${LYNX_TEST_CERT:-} ]]; then
    codesign --force --sign "$LYNX_TEST_CERT" "$OUT/PeerCodeRequirement" 2>/dev/null
    EXPECT_CERT_SHA1=$LYNX_TEST_CERT "$OUT/PeerCodeRequirement" || failed=1
fi

exit $failed
```

```sh
chmod +x Scripts/run-tests.sh
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `Scripts/run-tests.sh`
Expected: compile error, `cannot find 'MenuBarItemServiceIdentity' in scope` (the source files don't exist yet).

- [ ] **Step 3: Implement `Shared/Services/MenuBarItemServiceIdentity.swift`**

```swift
//
//  MenuBarItemServiceIdentity.swift
//  Shared
//

/// Derives the identifiers of the app and its `MenuBarItemService` helper
/// from each other, so neither is hardcoded.
///
/// The helper's bundle identifier is always the app's bundle identifier
/// plus ``serviceSuffix`` (see `LYNX_BUNDLE_ID` in `Config/Base.xcconfig`).
enum MenuBarItemServiceIdentity {
    /// The suffix that turns the app's bundle identifier into the helper's.
    static let serviceSuffix = ".MenuBarItemService"

    /// Returns the helper's service name for the given app identifier.
    static func serviceName(forHostIdentifier host: String) -> String {
        host + serviceSuffix
    }

    /// Returns the app identifier for the given helper identifier, or `nil`
    /// if the identifier doesn't belong to a helper.
    static func hostIdentifier(forServiceIdentifier service: String) -> String? {
        guard service.hasSuffix(serviceSuffix), service.count > serviceSuffix.count else {
            return nil
        }
        return String(service.dropLast(serviceSuffix.count))
    }
}
```

- [ ] **Step 4: Implement `Shared/Services/PeerCodeRequirement.swift`**

```swift
//
//  PeerCodeRequirement.swift
//  Shared
//

import CryptoKit
import Foundation
import Security

/// Builds code signing requirements that only match peers signed the
/// same way as the current process.
///
/// Lynx Bar is not built with an Apple Developer team, so the XPC
/// "same team" peer requirement can't be used. The app and its helper
/// require each other to be signed with the same certificate and to have
/// the expected signing identifier.
enum PeerCodeRequirement {
    /// How the current process is signed.
    enum Signer: Equatable, CustomStringConvertible {
        /// Signed with a certificate issued to an Apple Developer team.
        case team(String)
        /// Signed with a certificate that has no team, e.g. self-signed.
        /// The value is the lowercase hex SHA-1 of the leaf certificate.
        case certificate(sha1: String)

        var description: String {
            switch self {
            case .team(let team): "team \(team)"
            case .certificate(let sha1): "certificate \(sha1)"
            }
        }
    }

    /// Returns how the current process is signed, or `nil` if it is
    /// ad-hoc signed, unsigned, or its signature can't be read.
    static func currentSigner() -> Signer? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else {
            return nil
        }
        var cfInfo: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard
            SecCodeCopySigningInformation(staticCode, flags, &cfInfo) == errSecSuccess,
            let info = cfInfo as? [String: Any]
        else {
            return nil
        }
        if let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty {
            return .team(team)
        }
        guard
            let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let leaf = certificates.first
        else {
            return nil
        }
        let der = SecCertificateCopyData(leaf) as Data
        let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined()
        return .certificate(sha1: sha1)
    }

    /// Returns a requirement matching a peer with the given signing
    /// identifier that is signed by `signer`, or `nil` if there is no
    /// signer or any component would make a malformed requirement.
    static func requirement(for signer: Signer?, peerIdentifier: String) -> String? {
        guard isValid(peerIdentifier, allowed: identifierCharacters) else {
            return nil
        }
        switch signer {
        case .team(let team):
            guard isValid(team, allowed: teamCharacters) else {
                return nil
            }
            return "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\" and identifier \"\(peerIdentifier)\""
        case .certificate(let sha1):
            guard sha1.count == 40, isValid(sha1, allowed: hexCharacters) else {
                return nil
            }
            return "certificate leaf = H\"\(sha1)\" and identifier \"\(peerIdentifier)\""
        case nil:
            return nil
        }
    }

    /// Returns a requirement matching a peer with the given signing
    /// identifier that is signed the same way as the current process.
    static func requirement(forPeerIdentifier identifier: String) -> String? {
        requirement(for: currentSigner(), peerIdentifier: identifier)
    }

    private static let identifierCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    private static let teamCharacters = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
    private static let hexCharacters = CharacterSet(charactersIn: "0123456789abcdef")

    private static func isValid(_ string: String, allowed: CharacterSet) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy(allowed.contains)
    }
}
```

- [ ] **Step 5: Run the tests to make sure they pass**

```sh
Scripts/run-tests.sh
LYNX_TEST_CERT=E0ED98F7B2D56951B4E0A99082DEBAF25AF66311 Scripts/run-tests.sh
```

Expected: the first run prints `PASS PeerCodeRequirement`. The second prints it twice: the
ad-hoc run, then the certificate-signed run, whose signer is
`.certificate(sha1: "e0ed98f7…")`. Both exit 0.

- [ ] **Step 6: Build the app (the new Shared files compile into both targets)**

Run the ad-hoc build command. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit**

```sh
git add Scripts Shared/Services/MenuBarItemServiceIdentity.swift Shared/Services/PeerCodeRequirement.swift
git commit -m "Add helper identity derivation and same-certificate peer requirement

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Helper connection over the C XPC API, plus a "helper unavailable" state

**Files:**
- Modify: `Shared/Services/MenuBarItemService.swift` (whole file), `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift` (whole file), `MenuBarItemService/Listener.swift` (whole file), `MenuBarItemService/main.swift`, `Ice/Main/AppState.swift` (`setupTask`), `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`, `Ice/MenuBar/IceBar/IceBar.swift` (`content`), `Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`, `Ice/MenuBar/Search/MenuBarSearchPanel.swift` (`mainContent`)

**Interfaces:**
- Consumes: `MenuBarItemServiceIdentity`, `PeerCodeRequirement` (Task 3).
- Produces:
  - `MenuBarItemService.Connection.start() async -> String?`: `nil` on success, otherwise a
    failure description. `sourcePID(for:) async -> pid_t?` is unchanged.
  - `MenuBarItemService.encode(_:into:)`, `decode(_:from:)`, `describe(_:)` and `MessageError`.
  - `MenuBarItemManager.helperFailureReason: String?` (`@Published`, `private(set)`),
    `setHelperFailure(_ reason: String)`, and `static let helperUnavailableMessage: String`.
  - The `MenuBarItemService.name` constant is removed.

- [ ] **Step 1: Check who uses `MenuBarItemService.name`**

Run: `git grep -n "MenuBarItemService.name"`
Expected: only `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift` and `MenuBarItemService/Listener.swift`. If others appear, they must use `MenuBarItemServiceIdentity` in Step 2–4 too.

- [ ] **Step 2: Replace `Shared/Services/MenuBarItemService.swift`**

```swift
//
//  MenuBarItemService.swift
//  Shared
//

import Foundation
import XPC

/// Namespace for the `MenuBarItemService` XPC helper, which maps menu bar
/// item windows (owned by Control Center on macOS 26) to their source apps.
///
/// The service name is derived from the app's bundle identifier; see
/// ``MenuBarItemServiceIdentity``.
enum MenuBarItemService { }

extension MenuBarItemService {
    enum Request: Codable {
        case start
        case sourcePID(WindowInfo)
    }

    enum Response: Codable {
        case start
        case sourcePID(pid_t?)
    }
}

// MARK: - Message Coding

extension MenuBarItemService {
    /// An error that occurs when a message can't be encoded or decoded.
    struct MessageError: Error, CustomStringConvertible {
        let description: String
    }

    /// The dictionary key for a message's JSON payload.
    private static let payloadKey = "payload"

    /// Encodes a value as JSON into the given XPC dictionary.
    static func encode<T: Encodable>(_ value: T, into dictionary: xpc_object_t) throws {
        let data = try JSONEncoder().encode(value)
        data.withUnsafeBytes { buffer in
            xpc_dictionary_set_data(dictionary, payloadKey, buffer.baseAddress, buffer.count)
        }
    }

    /// Decodes a JSON value from the given XPC dictionary.
    static func decode<T: Decodable>(_ type: T.Type, from dictionary: xpc_object_t) throws -> T {
        var length = 0
        guard let bytes = xpc_dictionary_get_data(dictionary, payloadKey, &length) else {
            throw MessageError(description: "Message has no payload")
        }
        return try JSONDecoder().decode(type, from: Data(bytes: bytes, count: length))
    }

    /// Returns a readable description of an XPC object, e.g. an error.
    static func describe(_ object: xpc_object_t) -> String {
        if
            xpc_get_type(object) == XPC_TYPE_ERROR,
            let cString = xpc_dictionary_get_string(object, XPC_ERROR_KEY_DESCRIPTION)
        {
            return String(cString: cString)
        }
        return String(describing: object)
    }
}
```

- [ ] **Step 3: Replace `MenuBarItemService/Listener.swift`, and make `main.swift` call `Listener.run()`**

`MenuBarItemService/Listener.swift`:

```swift
//
//  Listener.swift
//  MenuBarItemService
//

import Foundation
import OSLog
import XPC

/// Accepts connections from the host app and answers its requests.
///
/// Every incoming connection must satisfy a code signing requirement that
/// only matches the host app, signed the same way as this service (see
/// ``PeerCodeRequirement``). If the service has no usable signature, or
/// its bundle identifier isn't a helper identifier, every connection is
/// refused.
enum Listener {
    /// The requirement that incoming peers must satisfy.
    private static let peerRequirement: String? = {
        guard
            let ownIdentifier = Bundle.main.bundleIdentifier,
            let host = MenuBarItemServiceIdentity.hostIdentifier(forServiceIdentifier: ownIdentifier)
        else {
            return nil
        }
        return PeerCodeRequirement.requirement(forPeerIdentifier: host)
    }()

    /// Handles a decoded request.
    private static func handle(_ request: MenuBarItemService.Request) -> MenuBarItemService.Response {
        switch request {
        case .start:
            Logger.default.debug("Listener received start request")
            return .start
        case .sourcePID(let window):
            return .sourcePID(SourcePIDCache.shared.pid(for: window))
        }
    }

    /// Handles an XPC event or message received on the given connection.
    private static func handle(event: xpc_object_t, on connection: xpc_connection_t) {
        guard xpc_get_type(event) == XPC_TYPE_DICTIONARY else {
            Logger.default.notice("Listener connection event: \(MenuBarItemService.describe(event), privacy: .public)")
            return
        }
        guard let reply = xpc_dictionary_create_reply(event) else {
            return
        }
        do {
            let request = try MenuBarItemService.decode(MenuBarItemService.Request.self, from: event)
            try MenuBarItemService.encode(handle(request), into: reply)
        } catch {
            Logger.default.error("Listener failed to handle message with error \(error)")
        }
        xpc_connection_send_message(connection, reply)
    }

    /// Configures and resumes a new peer connection, or refuses it.
    private static func accept(_ connection: xpc_connection_t) {
        guard let peerRequirement else {
            Logger.default.error("Refusing connection: service is not signed with a certificate")
            xpc_connection_cancel(connection)
            return
        }
        guard xpc_connection_set_peer_code_signing_requirement(connection, peerRequirement) == 0 else {
            Logger.default.error("Refusing connection: invalid peer requirement \(peerRequirement, privacy: .public)")
            xpc_connection_cancel(connection)
            return
        }
        xpc_connection_set_event_handler(connection) { event in
            handle(event: event, on: connection)
        }
        xpc_connection_resume(connection)
    }

    /// Starts handling connections. Never returns.
    ///
    /// The service's `RunLoopType` is `NSRunLoop` (see its Info.plist), so
    /// the main run loop keeps running for ``SourcePIDCache``.
    static func run() -> Never {
        Logger.default.notice("Starting listener, peer requirement: \(peerRequirement ?? "none", privacy: .public)")
        xpc_main { connection in
            Listener.accept(connection)
        }
    }
}
```

`MenuBarItemService/main.swift`:

```swift
//
//  main.swift
//  MenuBarItemService
//

import Foundation

SourcePIDCache.shared.start()
Listener.run()
```

- [ ] **Step 4: Replace `Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift`**

```swift
//
//  MenuBarItemServiceConnection.swift
//  Ice
//

import Foundation
import OSLog
import XPC

// MARK: - MenuBarItemService.Connection

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A connection to the `MenuBarItemService` XPC service.
    final class Connection: Sendable {
        /// The shared connection.
        static let shared = Connection()

        /// The connection's underlying session.
        private let session: Session

        /// The connection's logger.
        private let logger: Logger

        /// Creates a new connection.
        private init() {
            let queue = DispatchQueue.targetingGlobal(
                label: "MenuBarItemService.Connection.queue",
                qos: .userInteractive,
                attributes: .concurrent
            )
            let logger = Logger(category: "MenuBarItemService.Connection")
            self.session = Session(queue: queue, logger: logger)
            self.logger = logger
        }

        /// Starts the connection.
        ///
        /// - Returns: `nil` if the service answered, otherwise a description
        ///   of why it couldn't be reached.
        func start() async -> String? {
            logger.debug("Starting MenuBarItemService connection")
            do {
                let response = try session.send(request: .start)
                guard case .start = response else {
                    return "Start request returned invalid response \(response)"
                }
                return nil
            } catch {
                let reason = String(describing: error)
                logger.error("MenuBarItemService start failed: \(reason, privacy: .public)")
                return reason
            }
        }

        /// Returns the source process identifier for the given window.
        func sourcePID(for window: WindowInfo) async -> pid_t? {
            do {
                let response = try session.send(request: .sourcePID(window))
                guard case .sourcePID(let pid) = response else {
                    logger.error("Source PID request returned invalid response \(String(describing: response))")
                    return nil
                }
                return pid
            } catch {
                // Debug level: when the helper is refused, this fails for every
                // window on every refresh. `start()` already logged the reason.
                logger.debug("Source PID request failed: \(String(describing: error), privacy: .public)")
                return nil
            }
        }
    }
}

// MARK: - MenuBarItemService.ConnectionError

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// An error that prevents a request from reaching the service.
    enum ConnectionError: Error, CustomStringConvertible {
        /// The app has no certificate signature, so it can't require one from the service.
        case unsigned
        /// The generated peer requirement was rejected by XPC.
        case invalidRequirement(String)
        /// XPC returned an error, e.g. "Peer Forbidden".
        case xpc(String)

        var description: String {
            switch self {
            case .unsigned:
                "Lynx Bar is not signed with a certificate, so it won't connect to its helper"
            case .invalidRequirement(let requirement):
                "Invalid peer requirement: \(requirement)"
            case .xpc(let description):
                "XPC error: \(description)"
            }
        }
    }
}

// MARK: - MenuBarItemService.Session

@available(macOS 26.0, *)
extension MenuBarItemService {
    /// A wrapper around an XPC connection to the service.
    private final class Session: Sendable {
        /// A session's underlying storage. Only accessed under ``storage``'s lock.
        private final class Storage: @unchecked Sendable {
            private let serviceName = MenuBarItemServiceIdentity.serviceName(
                forHostIdentifier: Bundle.main.bundleIdentifier ?? ""
            )
            private let peerRequirement: String?
            private var connection: xpc_connection_t?
            private let queue: DispatchQueue
            private let logger: Logger

            init(queue: DispatchQueue, logger: Logger) {
                self.queue = queue
                self.logger = logger
                self.peerRequirement = PeerCodeRequirement.requirement(forPeerIdentifier: serviceName)
            }

            private func getOrCreateConnection() throws -> xpc_connection_t {
                if let connection {
                    return connection
                }
                guard let peerRequirement else {
                    throw ConnectionError.unsigned
                }
                let connection = xpc_connection_create(serviceName, queue)
                guard xpc_connection_set_peer_code_signing_requirement(connection, peerRequirement) == 0 else {
                    xpc_connection_cancel(connection)
                    throw ConnectionError.invalidRequirement(peerRequirement)
                }
                let logger = logger
                xpc_connection_set_event_handler(connection) { event in
                    if xpc_get_type(event) == XPC_TYPE_ERROR {
                        logger.warning("Connection event: \(MenuBarItemService.describe(event), privacy: .public)")
                    }
                }
                xpc_connection_resume(connection)
                logger.info("Connecting to \(self.serviceName, privacy: .public) requiring \(peerRequirement, privacy: .public)")
                self.connection = connection
                return connection
            }

            func cancel(reason: String) {
                guard let connection = connection.take() else {
                    return
                }
                logger.debug("Cancelling connection: \(reason)")
                xpc_connection_cancel(connection)
            }

            func send(request: Request) throws -> Response {
                let connection = try getOrCreateConnection()
                let message = xpc_dictionary_create_empty()
                try MenuBarItemService.encode(request, into: message)
                let reply = xpc_connection_send_message_with_reply_sync(connection, message)
                if xpc_get_type(reply) == XPC_TYPE_ERROR {
                    // An interrupted connection reconnects on the next message;
                    // any other error invalidates it, so start over next time.
                    if reply !== XPC_ERROR_CONNECTION_INTERRUPTED {
                        cancel(reason: "Received error \(MenuBarItemService.describe(reply))")
                    }
                    throw ConnectionError.xpc(MenuBarItemService.describe(reply))
                }
                return try MenuBarItemService.decode(Response.self, from: reply)
            }
        }

        /// Protected storage for the underlying XPC connection.
        private let storage: OSAllocatedUnfairLock<Storage>

        /// Creates a new session.
        init(queue: DispatchQueue, logger: Logger) {
            self.storage = OSAllocatedUnfairLock(initialState: Storage(queue: queue, logger: logger))
        }

        deinit {
            cancel(reason: "Session deinitialized")
        }

        /// Cancels the session.
        func cancel(reason: String) {
            storage.withLock { $0.cancel(reason: reason) }
        }

        /// Sends the given request to the service and returns the response.
        func send(request: Request) throws -> Response {
            try storage.withLock { try $0.send(request: request) }
        }
    }
}
```

- [ ] **Step 5: Add the failure state to `MenuBarItemManager`**

In `Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`, directly below
`@Published private(set) var itemCache = ItemCache(displayID: nil)`, add:

```swift

    /// Why the `MenuBarItemService` helper can't be used, or `nil` if it can.
    ///
    /// While this is set, items are neither cached nor moved, since items
    /// can't be told apart without the helper on macOS 26.
    @Published private(set) var helperFailureReason: String?

    /// The message shown in place of menu bar items while ``helperFailureReason`` is set.
    static let helperUnavailableMessage = "Lynx Bar's helper couldn't start. Build Lynx Bar with a signing certificate (see README)."

    /// Records that the `MenuBarItemService` helper can't be used.
    func setHelperFailure(_ reason: String) {
        logger.error("Menu bar item helper unavailable: \(reason, privacy: .public)")
        helperFailureReason = reason
        itemCache = ItemCache(displayID: nil)
    }
```

If the manager's logger property isn't called `logger`, use the existing name (check with
`grep -n "Logger(" Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift`).

Then, at the very top of `func cacheItemsRegardless(_ currentItemWindowIDs: [CGWindowID]? = nil) async {`,
before `await cacheActor.runCacheTask`, add:

```swift
        guard helperFailureReason == nil else {
            logger.debug("Skipping menu bar item cache: helper unavailable")
            return
        }
```

`cacheItemsIfNeeded()` calls `cacheItemsRegardless`, and item moves only target cached items,
so this keeps the manager from moving anything.

- [ ] **Step 6: Report start failures in `AppState`**

In `Ice/Main/AppState.swift`, in `setupTask`, replace:

```swift
        if #available(macOS 26.0, *) {
            await MenuBarItemService.Connection.shared.start()
        }
```

with:

```swift
        if #available(macOS 26.0, *) {
            if let failure = await MenuBarItemService.Connection.shared.start() {
                itemManager.setHelperFailure(failure)
            }
        }
```

- [ ] **Step 7: Show the message instead of "Loading menu bar items…"**

`Ice/MenuBar/IceBar/IceBar.swift`, in `content`, replace:

```swift
        } else if itemManager.itemCache.managedItems.isEmpty {
```

with:

```swift
        } else if itemManager.helperFailureReason != nil {
            Text(MenuBarItemManager.helperUnavailableMessage)
                .padding(.horizontal, 10)
        } else if itemManager.itemCache.managedItems.isEmpty {
```

`Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`, in `layoutBars`, replace:

```swift
            if !hasItems {
                loadingMenuBarItems
            }
```

with:

```swift
            if itemManager.helperFailureReason != nil {
                Text(MenuBarItemManager.helperUnavailableMessage)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if !hasItems {
                loadingMenuBarItems
            }
```

`Ice/MenuBar/Search/MenuBarSearchPanel.swift`, in `mainContent`, replace:

```swift
        if hasItems {
```

with:

```swift
        if itemManager.helperFailureReason != nil {
            Text(MenuBarItemManager.helperUnavailableMessage)
                .font(.title3)
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if hasItems {
```

- [ ] **Step 8: Build and lint**

Run the certificate build command (with `Config/Local.xcconfig` present), then
`swiftlint --strict Ice/MenuBar/MenuBarItems/MenuBarItemServiceConnection.swift Ice/MenuBar/MenuBarItems/MenuBarItemManager.swift Ice/Main/AppState.swift`.
Expected: `BUILD SUCCEEDED` and no lint output.

- [ ] **Step 9: Positive trust test (certificate-signed)**

```sh
pkill -x "Lynx Bar"; pkill -f "IceSpike.app/Contents/MacOS"; sleep 1
rm -rf ~/Applications/"Lynx Bar.app"
cp -R ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app" ~/Applications/
open ~/Applications/"Lynx Bar.app"
```

The first launch shows the permissions window. Grant Accessibility and Screen Recording to
**"Lynx Bar"**, then quit and reopen it. Then:

```sh
sleep 8
/usr/bin/log show --last 1m --info --style compact --predicate 'subsystem == "com.ikentrock.LynxBar" OR (process == "MenuBarItemService" AND eventMessage CONTAINS[c] "requirement")' | grep -iE "requirement|helper|forbidden|refus" | tail -5
```

Expected: the listener requires `identifier "com.ikentrock.LynxBar"` and the app requires
`identifier "com.ikentrock.LynxBar.MenuBarItemService"`, both with
`certificate leaf = H"e0ed98…"`. There are no "Refusing", "Forbidden" or "helper unavailable"
lines. **Owner check:** clicking the Lynx icon shows the shelf (still titled "Ice Bar"-style
until Task 8) with the hidden items.

- [ ] **Step 10: Negative trust test (helper with the right certificate but the wrong identifier)**

```sh
N=~/Library/Caches/lynx-bar-dev/LynxNeg.app; CERT=E0ED98F7B2D56951B4E0A99082DEBAF25AF66311
pkill -x "Lynx Bar"; sleep 1; rm -rf $N; cp -R ~/Applications/"Lynx Bar.app" $N
codesign -d --entitlements /tmp/lynx-ent.plist --xml ~/Applications/"Lynx Bar.app" 2>/dev/null
codesign --force --sign $CERT --identifier com.example.Impostor $N/Contents/XPCServices/MenuBarItemService.xpc
codesign --force --sign $CERT $( [ -s /tmp/lynx-ent.plist ] && echo --entitlements /tmp/lynx-ent.plist ) $N
open $N; sleep 8
/usr/bin/log show --last 20s --info --style compact --predicate 'subsystem == "com.ikentrock.LynxBar"' | grep -iE "forbidden|helper unavailable|Moving" | sort | uniq -c
pkill -f "LynxNeg.app/Contents/MacOS"; rm -rf $N /tmp/lynx-ent.plist
```

Expected: exactly one `Menu bar item helper unavailable: XPC error: Peer Forbidden` and **no
`Moving` lines**. If the owner opens the shelf, Layout pane or search during the run, each
shows the helper message.

- [ ] **Step 11: Negative trust test (ad-hoc build)**

```sh
mv Config/Local.xcconfig /tmp/Local.xcconfig.bak
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-adhoc build 2>&1 | grep -E "error:|BUILD" | sort -u
mv /tmp/Local.xcconfig.bak Config/Local.xcconfig
open ~/Library/Caches/lynx-bar-dev/dd-adhoc/Build/Products/Debug/"Lynx Bar.app"; sleep 8
/usr/bin/log show --last 20s --info --style compact --predicate 'subsystem == "com.ikentrock.LynxBar"' | grep -iE "helper unavailable|Moving" | sort | uniq -c
pkill -f "dd-adhoc/Build/Products/Debug/Lynx Bar.app"
```

Expected: `BUILD SUCCEEDED`, then either one `helper unavailable: Lynx Bar is not signed with
a certificate…` or, if the ad-hoc copy lacks Accessibility, the permissions window. Ad-hoc
builds lose their grants, which is expected and documented. There must be no `Moving` lines.
Afterwards, reopen `~/Applications/Lynx Bar.app`.

- [ ] **Step 12: Commit**

```sh
git add Shared MenuBarItemService Ice
git commit -m "Trust the helper by certificate and identifier, not team

Upstream's .isFromSameTeam() peer requirement rejects every connection in
builds without an Apple team. Use the C XPC API with a requirement derived
from each process's own signature (same certificate + expected identifier),
refuse connections from unsigned builds, and show a clear message instead of
an endless spinner. While the helper is unavailable, items are neither cached
nor moved.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Updates off unless a feed is configured

**Files:**
- Modify: `Ice/Resources/Info.plist`, `Ice/Main/Updates.swift`, `Ice/MenuBar/ControlItem/ControlItem.swift` (context menu)
- Inspect only: `Ice/UserNotifications/UserNotificationManager.swift`

**Interfaces:**
- Produces: `UpdatesManager.isAvailable: Bool` (static, `true` only if `SUFeedURL` is in
  Info.plist). When it's `false`, Sparkle's `SPUStandardUpdaterController` is never created.

- [ ] **Step 1: Remove the Ice feed from `Ice/Resources/Info.plist`**

Replace the whole file with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<!--
	No update feed: Lynx Bar doesn't publish releases yet. To enable updates,
	add SUFeedURL and SUPublicEDKey for Lynx Bar's own Sparkle feed.
	-->
</dict>
</plist>
```

- [ ] **Step 2: Gate `UpdatesManager`**

In `Ice/Main/Updates.swift`:

(a) After `@Published var lastUpdateCheckDate: Date?`, add:

```swift

    /// A Boolean value that indicates whether this build has an update feed.
    ///
    /// Without `SUFeedURL` in Info.plist, Sparkle is never started.
    static let isAvailable = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") is String
```

(b) Replace the two computed properties' getters and setters so they don't touch Sparkle
when updates are unavailable:

```swift
    /// A Boolean value that indicates whether to automatically check for updates.
    var automaticallyChecksForUpdates: Bool {
        get {
            Self.isAvailable && updater.automaticallyChecksForUpdates
        }
        set {
            guard Self.isAvailable else {
                return
            }
            objectWillChange.send()
            updater.automaticallyChecksForUpdates = newValue
        }
    }

    /// A Boolean value that indicates whether to automatically download updates.
    var automaticallyDownloadsUpdates: Bool {
        get {
            Self.isAvailable && updater.automaticallyDownloadsUpdates
        }
        set {
            guard Self.isAvailable else {
                return
            }
            objectWillChange.send()
            updater.automaticallyDownloadsUpdates = newValue
        }
    }
```

(c) In `performSetup(with:)`, replace the body with:

```swift
        self.appState = appState
        guard Self.isAvailable else {
            return
        }
        _ = updaterController
        configureCancellables()
```

(d) At the start of `checkForUpdates()`, before `#if DEBUG`, add:

```swift
        guard Self.isAvailable else {
            return
        }
```

- [ ] **Step 3: Hide "Check for Updates…" in the menu bar item's menu**

In `Ice/MenuBar/ControlItem/ControlItem.swift`, replace:

```swift
        let checkForUpdatesItem = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdatesItem.target = self
        menu.addItem(checkForUpdatesItem)

        menu.addItem(.separator())
```

with:

```swift
        if UpdatesManager.isAvailable {
            let checkForUpdatesItem = NSMenuItem(
                title: "Check for Updates…",
                action: #selector(checkForUpdates),
                keyEquivalent: ""
            )
            checkForUpdatesItem.target = self
            menu.addItem(checkForUpdatesItem)

            menu.addItem(.separator())
        }
```

`UserNotificationManager`'s `.updateCheck` branch calls `checkForUpdates()`, which now
returns early, so it needs no change. Confirm with
`grep -n "checkForUpdates" Ice/UserNotifications/UserNotificationManager.swift`.

- [ ] **Step 4: Verify that nothing reaches Sparkle**

Build with the certificate, install as in Task 4 Step 9, and launch. Then:

```sh
sleep 5; PID=$(pgrep -x "Lynx Bar")
nettop -p $PID -L 1 -J bytes_in,bytes_out 2>/dev/null | head -5
/usr/bin/log show --last 1m --style compact --predicate 'process == "Lynx Bar" AND (subsystem BEGINSWITH "org.sparkle-project" OR eventMessage CONTAINS[c] "appcast")' | tail -3
plutil -p ~/Applications/"Lynx Bar.app"/Contents/Info.plist | grep -i SU   # expect: no output
```

Expected: no Sparkle or appcast log lines, and no `SU*` keys. Right-clicking the Lynx icon
shows a menu without "Check for Updates…".

- [ ] **Step 5: Commit**

```sh
git add Ice/Resources/Info.plist Ice/Main/Updates.swift Ice/MenuBar/ControlItem/ControlItem.swift
git commit -m "Turn off updates unless an update feed is configured

Remove Ice's Sparkle feed and key so Lynx Bar can never update itself to Ice.
Sparkle only starts when SUFeedURL is present.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

(The About pane's Updates section is changed in Task 8.)

---

### Task 6: One-time import of Ice's settings

**Files:**
- Create: `Ice/Utilities/IceSettingsImporter.swift`, `Scripts/Tests/IceSettingsImporter/main.swift`
- Modify: `Scripts/run-tests.sh`, `Ice/Main/AppDelegate.swift`

**Interfaces:**
- Produces:
  - `enum IceSettingsImporter`:
    - `static let sourceDomain = "com.jordanbaird.Ice"`
    - `static let importedFlagKey = "hasImportedIceSettings"`
    - `enum Outcome: Equatable { case alreadyImported, noSourceSettings, imported(keyCount: Int) }`
    - `@discardableResult static func importIfNeeded(source: [String: Any]?, into defaults: UserDefaults) -> Outcome`
    - `@discardableResult static func importIfNeeded() -> Outcome`

- [ ] **Step 1: Write the failing test**

`Scripts/Tests/IceSettingsImporter/main.swift`:

```swift
//
//  main.swift
//  Tests
//

import Foundation

/// Creates a scratch defaults domain and removes it afterwards.
func withScratchDefaults(_ body: (UserDefaults) -> Void) {
    let name = "com.ikentrock.LynxBar.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)! // swiftlint:disable:this force_unwrapping
    body(defaults)
    defaults.removePersistentDomain(forName: name)
}

// Imports everything on first run and sets the flag.
withScratchDefaults { defaults in
    let source: [String: Any] = ["UseIceBar": true, "IceBarLocation": 2, "Ice.ControlItem.Hidden": 481]
    let outcome = IceSettingsImporter.importIfNeeded(source: source, into: defaults)
    expect(outcome == .imported(keyCount: 3), "imports all keys (got \(outcome))")
    expect(defaults.bool(forKey: "UseIceBar"), "copies a Bool")
    expect(defaults.integer(forKey: "IceBarLocation") == 2, "copies an Int")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "sets the flag")
}

// Never overwrites values Lynx Bar already has.
withScratchDefaults { defaults in
    defaults.set(5, forKey: "IceBarLocation")
    let outcome = IceSettingsImporter.importIfNeeded(source: ["IceBarLocation": 2, "UseIceBar": true], into: defaults)
    expect(outcome == .imported(keyCount: 1), "imports only missing keys (got \(outcome))")
    expect(defaults.integer(forKey: "IceBarLocation") == 5, "keeps the existing value")
}

// Runs only once.
withScratchDefaults { defaults in
    IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults)
    defaults.set(false, forKey: "UseIceBar")
    let outcome = IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults)
    expect(outcome == .alreadyImported, "second run is a no-op (got \(outcome))")
    expect(!defaults.bool(forKey: "UseIceBar"), "second run doesn't copy again")
}

// Missing or empty source: nothing copied, but the flag is set (first launch or never).
withScratchDefaults { defaults in
    expect(IceSettingsImporter.importIfNeeded(source: nil, into: defaults) == .noSourceSettings, "nil source")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "flag set without source")
    expect(IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults) == .alreadyImported,
           "a later Ice install isn't imported")
}
withScratchDefaults { defaults in
    expect(IceSettingsImporter.importIfNeeded(source: [:], into: defaults) == .noSourceSettings, "empty source")
}

// The source's own flag key is never copied.
withScratchDefaults { defaults in
    let outcome = IceSettingsImporter.importIfNeeded(source: [IceSettingsImporter.importedFlagKey: false, "A": 1], into: defaults)
    expect(outcome == .imported(keyCount: 1), "skips the flag key (got \(outcome))")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "flag ends up true")
}

finishTests("IceSettingsImporter")
```

Add to `Scripts/run-tests.sh`, before `exit $failed`:

```sh
build IceSettingsImporter ../Ice/Utilities/IceSettingsImporter.swift ../Shared/Utilities/Logging.swift
run IceSettingsImporter
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `Scripts/run-tests.sh`
Expected: `PASS PeerCodeRequirement`, then a compile error, `cannot find 'IceSettingsImporter' in scope`.

- [ ] **Step 3: Implement `Ice/Utilities/IceSettingsImporter.swift`**

```swift
//
//  IceSettingsImporter.swift
//  Ice
//

import Foundation
import OSLog

/// Copies Ice's settings into Lynx Bar's defaults on first launch.
///
/// Lynx Bar has its own bundle identifier, so it starts with an empty
/// defaults domain. This runs before any settings are read, and before
/// `MigrationManager`, so imported settings in older formats still get
/// migrated. Ice's own domain is only read.
enum IceSettingsImporter {
    /// The defaults domain of Ice.
    static let sourceDomain = "com.jordanbaird.Ice"

    /// The key that records that the import has run.
    static let importedFlagKey = "hasImportedIceSettings"

    /// The result of an import attempt.
    enum Outcome: Equatable {
        /// The import already ran on an earlier launch.
        case alreadyImported
        /// Ice has no settings to import.
        case noSourceSettings
        /// The given number of keys were copied.
        case imported(keyCount: Int)
    }

    private static let logger = Logger(category: "IceSettingsImporter")

    /// Copies keys from `source` that `defaults` doesn't have yet, once.
    ///
    /// The flag is set even if there is nothing to import, so the import
    /// happens on the first launch or never.
    @discardableResult
    static func importIfNeeded(source: [String: Any]?, into defaults: UserDefaults) -> Outcome {
        guard !defaults.bool(forKey: importedFlagKey) else {
            return .alreadyImported
        }
        defer {
            defaults.set(true, forKey: importedFlagKey)
        }
        guard let source, !source.isEmpty else {
            return .noSourceSettings
        }
        var count = 0
        for (key, value) in source where key != importedFlagKey && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            count += 1
        }
        return .imported(keyCount: count)
    }

    /// Imports Ice's settings into the standard defaults, once.
    @discardableResult
    static func importIfNeeded() -> Outcome {
        let outcome = importIfNeeded(
            source: UserDefaults.standard.persistentDomain(forName: sourceDomain),
            into: .standard
        )
        logger.info("Ice settings import: \(String(describing: outcome), privacy: .public)")
        return outcome
    }
}
```

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `Scripts/run-tests.sh`
Expected: `PASS PeerCodeRequirement` and `PASS IceSettingsImporter`, exit 0.

- [ ] **Step 5: Run the importer before `AppState` exists**

`AppState()` builds the settings models, so the import must happen first. In
`Ice/Main/AppDelegate.swift`, replace:

```swift
    /// The shared app state.
    let appState = AppState()
```

with:

```swift
    /// The shared app state.
    let appState: AppState

    override init() {
        // Must run before AppState reads any settings, and before migrations.
        IceSettingsImporter.importIfNeeded()
        self.appState = AppState()
        super.init()
    }
```

- [ ] **Step 6: Build, lint, and check against your real settings**

```sh
swiftlint --strict Ice/Utilities/IceSettingsImporter.swift Ice/Main/AppDelegate.swift
# build with certificate, then:
pkill -x "Lynx Bar"; sleep 1
defaults delete com.ikentrock.LynxBar 2>/dev/null; true
rm -rf ~/Applications/"Lynx Bar.app"; cp -R ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app" ~/Applications/
open ~/Applications/"Lynx Bar.app"; sleep 5
defaults read com.ikentrock.LynxBar hasImportedIceSettings      # expect: 1
for k in UseIceBar IceBarLocation ShowOnHover; do echo "$k: ice=$(defaults read com.jordanbaird.Ice $k 2>/dev/null) lynx=$(defaults read com.ikentrock.LynxBar $k 2>/dev/null)"; done
```

Expected: no lint output; the flag is `1`; each key's Lynx value equals Ice's. The menu bar
sections look the way they did in Ice. Ice's domain is unchanged (`defaults read
com.jordanbaird.Ice | wc -l` gives the same count before and after).

- [ ] **Step 7: Commit**

```sh
git add Ice/Utilities/IceSettingsImporter.swift Ice/Main/AppDelegate.swift Scripts
git commit -m "Import Ice's settings once on first launch

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Lynx artwork and the Lynx icon image set

**Files:**
- Create: `Resources/Artwork/AppIcon.svg`, `Resources/Artwork/LynxFill.svg`, `Resources/Artwork/LynxStroke.svg`, `Resources/Artwork/render.swift`
- Rename: `Ice/Resources/Assets.xcassets/ControlItemImages/IceCube/` → `…/Lynx/` (with `LynxFill.imageset`, `LynxStroke.imageset`)
- Modify: `Ice/Resources/Assets.xcassets/AppIcon.appiconset/*.png`, `Ice/MenuBar/ControlItem/ControlItemImageSet.swift`, `Ice/Main/Navigation/NavigationIdentifiers/SettingsNavigationIdentifier.swift`, `Ice/MenuBar/Search/MenuBarSearchPanel.swift`

**Interfaces:**
- Produces: `ControlItemImageSet.Name.lynx` (raw value `"Lynx"`, which also decodes from the
  legacy `"Ice Cube"`), `static let ControlItemImageSet.lynx`, `defaultIceIcon == .lynx`, and
  asset symbols `.lynxFill` and `.lynxStroke`. `.iceCubeFill` and `.iceCubeStroke` no longer
  exist.

- [ ] **Step 1: Write the glyph SVGs**

`Resources/Artwork/LynxFill.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
  <!-- Lynx head with tufted ears; eyes and nose are cut out (even-odd). -->
  <path fill="#000" fill-rule="evenodd" d="M3 10 L3.6 2.2 L4 0.6 L4.6 2.4 L8 6 H12 L15.4 2.4 L16 0.6 L16.4 2.2 L17 10 C17 14.5 14 17.5 10 19 C6 17.5 3 14.5 3 10 Z M6 10.5 L8.8 11.2 L7.2 12.8 Z M14 10.5 L11.2 11.2 L12.8 12.8 Z M9 14.5 H11 L10 15.6 Z"/>
</svg>
```

`Resources/Artwork/LynxStroke.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">
  <path fill="none" stroke="#000" stroke-width="1.4" stroke-linejoin="round" d="M3 10 L3.6 2.2 L4 0.6 L4.6 2.4 L8 6 H12 L15.4 2.4 L16 0.6 L16.4 2.2 L17 10 C17 14.5 14 17.5 10 19 C6 17.5 3 14.5 3 10 Z"/>
  <path fill="#000" d="M6 10.5 L8.8 11.2 L7.2 12.8 Z M14 10.5 L11.2 11.2 L12.8 12.8 Z M9 14.5 H11 L10 15.6 Z"/>
</svg>
```

`Resources/Artwork/AppIcon.svg`:

```xml
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#E9A23B"/>
      <stop offset="1" stop-color="#B8641F"/>
    </linearGradient>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg)"/>
  <g transform="translate(212 196) scale(30)">
    <path fill="#FFF8EE" fill-rule="evenodd" d="M3 10 L3.6 2.2 L4 0.6 L4.6 2.4 L8 6 H12 L15.4 2.4 L16 0.6 L16.4 2.2 L17 10 C17 14.5 14 17.5 10 19 C6 17.5 3 14.5 3 10 Z M6 10.5 L8.8 11.2 L7.2 12.8 Z M14 10.5 L11.2 11.2 L12.8 12.8 Z M9 14.5 H11 L10 15.6 Z"/>
  </g>
</svg>
```

- [ ] **Step 2: Rename the IceCube asset folder to Lynx**

```sh
A=Ice/Resources/Assets.xcassets/ControlItemImages
git mv $A/IceCube $A/Lynx
git mv $A/Lynx/IceCubeFill.imageset $A/Lynx/LynxFill.imageset
git mv $A/Lynx/IceCubeStroke.imageset $A/Lynx/LynxStroke.imageset
git rm -q $A/Lynx/LynxFill.imageset/IceCubeFill.png $A/Lynx/LynxStroke.imageset/IceCubeStroke.png
sed -i '' 's/IceCubeFill\.png/LynxFill.png/' $A/Lynx/LynxFill.imageset/Contents.json
sed -i '' 's/IceCubeStroke\.png/LynxStroke.png/' $A/Lynx/LynxStroke.imageset/Contents.json
grep filename $A/Lynx/*/Contents.json
```

Expected: `"filename" : "LynxFill.png"` and `"filename" : "LynxStroke.png"`. The
`template-rendering-intent: template` property stays.

- [ ] **Step 3: Write `Resources/Artwork/render.swift`**

```swift
//
//  render.swift
//  Artwork
//
//  Renders Lynx Bar's SVG artwork into the asset catalog.
//  Run from the repository root:  swift Resources/Artwork/render.swift
//

import AppKit

func render(_ svgPath: String, pixels: Int, to pngPath: String) {
    guard let image = NSImage(contentsOf: URL(fileURLWithPath: svgPath)) else {
        fatalError("Can't load \(svgPath)")
    }
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("Can't create bitmap")
    }
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("Can't encode \(pngPath)")
    }
    do {
        try data.write(to: URL(fileURLWithPath: pngPath))
    } catch {
        fatalError("Can't write \(pngPath): \(error)")
    }
    print("wrote \(pngPath)")
}

let assets = "Ice/Resources/Assets.xcassets"
let appIconSizes = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in appIconSizes {
    render("Resources/Artwork/AppIcon.svg", pixels: pixels, to: "\(assets)/AppIcon.appiconset/\(name).png")
}
// Control item images are 20 pt, provided at 2x (40 px), like the other image sets.
for name in ["LynxFill", "LynxStroke"] {
    render("Resources/Artwork/\(name).svg", pixels: 40, to: "\(assets)/ControlItemImages/Lynx/\(name).imageset/\(name).png")
}
```

- [ ] **Step 4: Render and look at the result**

```sh
swift Resources/Artwork/render.swift
sips -g pixelWidth Ice/Resources/Assets.xcassets/ControlItemImages/Lynx/LynxFill.imageset/LynxFill.png Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png
```

Expected: 12 `wrote` lines and widths of 40 and 1024. Open
`Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512@2x.png` and `LynxFill.png` with
the Read tool (or Quick Look) and check visually: an amber rounded square with a pale lynx head
showing two tufted ears, eyes and a nose, and a solid black glyph with transparent eyes. If
CoreSVG drops the gradient, change the `rect`'s `fill` to the solid `#D1832D` and re-render.

- [ ] **Step 5: Update `ControlItemImageSet`**

In `Ice/MenuBar/ControlItem/ControlItemImageSet.swift`:

(a) Replace the `Name` enum with:

```swift
    enum Name: String, Codable, Hashable {
        case arrow = "Arrow"
        case chevron = "Chevron"
        case door = "Door"
        case dot = "Dot"
        case ellipsis = "Ellipsis"
        case lynx = "Lynx"
        case sunglasses = "Sunglasses"
        case custom = "Custom"

        /// The name Ice stored for its "Ice Cube" set, replaced by ``lynx``.
        private static let legacyIceCube = "Ice Cube"

        init(from decoder: any Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            if rawValue == Self.legacyIceCube {
                self = .lynx
            } else if let name = Self(rawValue: rawValue) {
                self = name
            } else {
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown image set name \(rawValue)"
                ))
            }
        }
    }
```

(b) Below `init(name: Name, image: ControlItemImage)`, add:

```swift

    private enum CodingKeys: String, CodingKey {
        case name, hidden, visible
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(Name.self, forKey: .name)
        if name == .lynx {
            // Stored "Ice Cube" sets point at deleted IceCube assets; always use
            // the current Lynx images.
            self = .lynx
            return
        }
        self.init(
            name: name,
            hidden: try container.decode(ControlItemImage.self, forKey: .hidden),
            visible: try container.decode(ControlItemImage.self, forKey: .visible)
        )
    }
```

(c) Replace the `defaultIceIcon` definition and the `.iceCube` entry in
`userSelectableIceIcons`:

```swift
    /// The Lynx image set.
    static let lynx = ControlItemImageSet(
        name: .lynx,
        hidden: .catalog("LynxStroke"),
        visible: .catalog("LynxFill")
    )

    /// The default image set for the Lynx icon.
    static let defaultIceIcon = lynx
```

and in the `userSelectableIceIcons` array replace

```swift
        ControlItemImageSet(
            name: .iceCube,
            hidden: .catalog("IceCubeStroke"),
            visible: .catalog("IceCubeFill")
        ),
```

with

```swift
        lynx,
```

(d) Update the doc comments: "The image sets that the user can choose to display in the Lynx icon."

- [ ] **Step 6: Replace the remaining IceCube references, build, and test legacy decoding**

```sh
sed -i '' 's/\.iceCubeStroke/.lynxStroke/' Ice/Main/Navigation/NavigationIdentifiers/SettingsNavigationIdentifier.swift Ice/MenuBar/Search/MenuBarSearchPanel.swift
git grep -n -i "icecube\|ice cube\|\.iceCube" -- Ice
```

Expected: only the `legacyIceCube = "Ice Cube"` line. Then run the certificate build
(expect `BUILD SUCCEEDED`) and `swiftlint --strict Ice/MenuBar/ControlItem/ControlItemImageSet.swift`
(expect no output).

Legacy decoding check. This writes a stored Ice Cube set into Lynx Bar's defaults the way Ice
saved it:

```sh
pkill -x "Lynx Bar"; sleep 1
defaults read com.ikentrock.LynxBar IceIcon > /tmp/lynx-iceicon-backup.txt 2>/dev/null; true
python3 - <<'EOF'
import json, subprocess
v = json.dumps({"name": "Ice Cube", "hidden": {"catalog": {"_0": "IceCubeStroke"}}, "visible": {"catalog": {"_0": "IceCubeFill"}}})
subprocess.run(["defaults", "write", "com.ikentrock.LynxBar", "IceIcon", "-data", v.encode().hex()], check=True)
EOF
rm -rf ~/Applications/"Lynx Bar.app"; cp -R ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Debug/"Lynx Bar.app" ~/Applications/
open ~/Applications/"Lynx Bar.app"; sleep 5
/usr/bin/log show --last 30s --style compact --predicate 'subsystem == "com.ikentrock.LynxBar" AND eventMessage CONTAINS "Error decoding"' | tail -2
```

Expected: no "Error decoding" lines. The menu bar shows the **Lynx glyph**, and Settings →
General → Lynx icon picker shows "Lynx" selected.

If the stored JSON shape for `ControlItemImage.catalog` differs, the log shows a decoding error
from the *images*, not the name. Fix the test value to match what `ControlItemImage` encodes,
which you can print from a debug build with
`String(data: try JSONEncoder().encode(ControlItemImageSet.lynx), encoding: .utf8)`. Don't
change the decoder. Afterwards, restore your real choice: pick it again in Settings, or
`defaults delete com.ikentrock.LynxBar IceIcon` if the backup file was empty.

- [ ] **Step 7: Commit**

```sh
git add Resources/Artwork Ice
git commit -m "Add placeholder Lynx artwork and make Lynx the default icon

The app icon and Lynx control item images are rendered from SVG sources in
Resources/Artwork. The Ice Cube set is replaced by Lynx; stored 'Ice Cube'
settings decode to the Lynx set.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: User-facing copy, About pane and accessibility label

**Files:**
- Modify: `Ice/Settings/SettingsPanes/AboutSettingsPane.swift`, `Ice/Settings/SettingsView.swift`, `Ice/UI/IceUI/IceWindow.swift`, `Ice/MenuBar/ControlItem/ControlItem.swift`, `Ice/MenuBar/MenuBarManager.swift`, `Ice/MenuBar/IceBar/IceBar.swift`, `Ice/MenuBar/IceBar/IceBarLocation.swift`, `Ice/MenuBar/Appearance/MenuBarAppearanceEditor/MenuBarAppearanceEditor.swift`, `Ice/Permissions/PermissionsView.swift`, `Ice/Settings/SettingsPanes/GeneralSettingsPane.swift`, `Ice/Settings/SettingsPanes/AdvancedSettingsPane.swift`, `Ice/Settings/SettingsPanes/HotkeysSettingsPane.swift`, `Ice/Settings/SettingsPanes/MenuBarLayoutSettingsPane.swift`, `Ice/MenuBar/Search/MenuBarSearchPanel.swift`

**Interfaces:**
- Consumes: `UpdatesManager.isAvailable` (Task 5).

- [ ] **Step 1: Replace user-facing strings**

Apply exactly these replacements. Each "before" occurs once; check with `git grep -n` first.

| File | Before | After |
|---|---|---|
| `MenuBarAppearanceEditor.swift` | `"Ice cannot edit the appearance of automatically hidden menu bars."` | `"Lynx Bar cannot edit the appearance of automatically hidden menu bars."` |
| `ControlItem.swift` | `NSMenu(title: "Ice")` | `NSMenu(title: "Lynx Bar")` |
| `ControlItem.swift` | `title: "Ice Settings…",` | `title: "Lynx Bar Settings…",` |
| `ControlItem.swift` | `title: "Quit Ice",` | `title: "Quit Lynx Bar",` |
| `MenuBarManager.swift` | `NSMenu(title: "Ice")` | `NSMenu(title: "Lynx Bar")` |
| `MenuBarManager.swift` | `title: "Ice Settings…",` | `title: "Lynx Bar Settings…",` |
| `IceBar.swift` | `self.title = "Ice Bar"` | `self.title = "Lynx Shelf"` |
| `IceBar.swift` | `"The Ice Bar requires screen recording permissions."` | `"The Lynx Shelf requires screen recording permissions."` |
| `IceBar.swift` | `Text("Open Ice Settings")` | `Text("Open Lynx Bar Settings")` |
| `IceBar.swift` | `"Ice cannot display menu bar items for automatically hidden menu bars"` | `"Lynx Bar cannot display menu bar items for automatically hidden menu bars"` |
| `IceBarLocation.swift` | `case .iceIcon: "Ice icon"` | `case .iceIcon: "Lynx icon"` |
| `PermissionsView.swift` | `"Ice needs your permission to manage the menu bar."` | `"Lynx Bar needs your permission to manage the menu bar."` |
| `PermissionsView.swift` | `"Ice needs this to:"` | `"Lynx Bar needs this to:"` |
| `PermissionsView.swift` | `"Ice can work in a limited mode without this permission."` | `"Lynx Bar can work in a limited mode without this permission."` |
| `GeneralSettingsPane.swift` | `Toggle("Show Ice icon", ` | `Toggle("Show Lynx icon", ` |
| `GeneralSettingsPane.swift` | `"Click to show hidden menu bar items. Right-click to access Ice's settings."` | `"Click to show hidden menu bar items. Right-click to access Lynx Bar's settings."` |
| `GeneralSettingsPane.swift` | `LocalizedStringKey("Ice icon")` | `LocalizedStringKey("Lynx icon")` |
| `GeneralSettingsPane.swift` | `Toggle("Use Ice Bar", ` | `Toggle("Use Lynx Shelf", ` |
| `GeneralSettingsPane.swift` | `"The Ice Bar's location changes based on context."` | `"The Lynx Shelf's location changes based on context."` |
| `GeneralSettingsPane.swift` | `"The Ice Bar is centered below the mouse pointer."` | `"The Lynx Shelf is centered below the mouse pointer."` |
| `GeneralSettingsPane.swift` | `"The Ice Bar is centered below the Ice icon."` | `"The Lynx Shelf is centered below the Lynx icon."` |
| `AdvancedSettingsPane.swift` | `version of Ice's menu.` | `version of Lynx Bar's menu.` |
| `HotkeysSettingsPane.swift` | `Text("Enable the Ice Bar")` | `Text("Enable the Lynx Shelf")` |
| `MenuBarLayoutSettingsPane.swift` | `"Ice cannot arrange menu bar items in automatically hidden menu bars."` | `"Lynx Bar cannot arrange menu bar items in automatically hidden menu bars."` |
| `SettingsView.swift` | `Text("Ice")` (sidebar header) | `Text("Lynx Bar")` |
| `IceWindow.swift` | `case .settings: "Ice"` | `case .settings: "Lynx Bar"` |

Also check `GeneralSettingsPane.swift` for other sections labelled with "Ice Bar"
(`git grep -n "Ice" Ice/Settings/SettingsPanes/GeneralSettingsPane.swift`) and rename those
too. Leave `// MARK:` comments, identifiers and raw values alone.

The sidebar header font is sized for "Ice": `.font(.system(size: sidebarFontSize * 2.67, …))`.
For "Lynx Bar", use `sidebarFontSize * 1.8`, so the line fits the sidebar. Check it in Step 5.

- [ ] **Step 2: Accessibility label for the Lynx icon**

In `Ice/MenuBar/ControlItem/ControlItem.swift`, in `StatusItemStorage.init`, after
`button.sendAction(on: [.leftMouseDown, .rightMouseUp])` add:

```swift
                if controlItem.identifier == .visible {
                    button.setAccessibilityLabel("Lynx Bar")
                }
```

(`.visible` is the identifier of the control item that shows the Lynx icon. Check with
`grep -n "case visible" Ice/MenuBar/ControlItem/ControlItem.swift`.)

- [ ] **Step 3: Rework the About pane**

In `Ice/Settings/SettingsPanes/AboutSettingsPane.swift`:

(a) Replace the URL properties (`contributeURL`, `issuesURL`, `donateURL`) with:

```swift
    private var contributeURL: URL {
        URL(string: "https://github.com/ikentrock/lynx-bar")! // swiftlint:disable:this force_unwrapping
    }

    private var issuesURL: URL {
        contributeURL.appendingPathComponent("issues")
    }

    private var upstreamURL: URL {
        URL(string: "https://github.com/jordanbaird/Ice")! // swiftlint:disable:this force_unwrapping
    }
```

Keep the existing `acknowledgementsURL` property, but use the same trailing
`// swiftlint:disable:this force_unwrapping` form in place of the `disable:next` line above it.
Run lint in Step 5. If SwiftLint reports `superfluous_disable_command` for any of these,
remove that comment (newer SwiftLint doesn't flag force-unwrapped URL literals).

(b) In `appIconAndCopyrightSection`:
- `Text("Ice").font(.system(size: 80))` becomes `Text("Lynx Bar").font(.system(size: 64))`.
- `.aspectRatio(contentMode: .fit)` becomes `.scaledToFit()` (fixes the existing
  `legacy_swiftui_aspect_ratio` violation).

(c) Replace `updatesSection` with:

```swift
    @ViewBuilder
    private var updatesSection: some View {
        IceSection(options: .hasDividers) {
            if UpdatesManager.isAvailable {
                automaticallyCheckForUpdates
                automaticallyDownloadUpdates
                if updatesManager.canCheckForUpdates {
                    checkForUpdates
                }
            } else {
                Text("Updates are not available in this build.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: 600)
    }
```

(d) In `bottomBar`:
- `Button("Quit Ice")` becomes `Button("Quit Lynx Bar")`.
- Remove the `Button("Support Ice", systemImage: "heart.circle.fill") { openURL(donateURL) }`
  button.
- After the "Report a Bug" button, add:

```swift
            Button("Based on Ice") {
                openURL(upstreamURL)
            }
            .help("Lynx Bar is based on Ice by Jordan Baird")
```

- [ ] **Step 4: Fix the pre-existing lint violations in touched files**

```sh
swiftlint --strict Ice/Permissions/PermissionsView.swift Ice/MenuBar/Search/MenuBarSearchPanel.swift Ice/Settings/SettingsPanes/AboutSettingsPane.swift
```

For each `legacy_swiftui_aspect_ratio` violation, replace `.aspectRatio(contentMode: .fit)`
with `.scaledToFit()`, or `.aspectRatio(contentMode: .fill)` with `.scaledToFill()`. Re-run
until there's no output.

- [ ] **Step 5: Build, lint everything and look at it**

```sh
swiftlint --strict 2>&1 | grep -v "IconResource.swift" | head
git grep -n '"[^"]*\bIce\b[^"]*"' -- Ice | grep -vE 'Logger|logger|rawValue|case [a-zA-Z]+ = "|Ice\.ControlItem|legacyIceCube|jordanbaird/Ice|"Based on Ice'
```

Expected: no lint output except the untouched `IconResource.swift` (pre-existing, out of
scope). The grep returns nothing. If it finds a user-visible string, rename it following
Step 1's pattern.

Build with the certificate, install as in Task 4 Step 9, and check with the owner:
- Settings sidebar: "Lynx Bar", fitting on one line.
- About pane: "Lynx Bar", version 0.12.0, copyright line, "Updates are not available in this
  build.", and the buttons Quit Lynx Bar / Acknowledgements / Contribute / Report a Bug /
  Based on Ice.
- General: "Show Lynx icon", "Use Lynx Shelf".
- The shelf's permission or loading texts read "Lynx Shelf".
- VoiceOver (⌘F5) on the Lynx icon reads "Lynx Bar".

- [ ] **Step 6: Commit**

```sh
git add Ice
git commit -m "Say Lynx Bar everywhere users look

Rename user-facing Ice strings (the Ice Bar is now the Lynx Shelf, the Ice
icon the Lynx icon), point the About pane at this repo with credit to Ice,
drop the donation button, and explain that updates are unavailable.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Repository docs

**Files:**
- Modify: `README.md` (whole file), `FREQUENT_ISSUES.md`, `.github/ISSUE_TEMPLATE/bug_report.yml`, `.github/ISSUE_TEMPLATE/config.yml` (if it links upstream), `CLAUDE.md`
- Delete: `.github/FUNDING.yml`

- [ ] **Step 1: Replace `README.md`**

```markdown
<div align="center">
    <img src="Ice/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width=200 height=200>
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
   xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release build
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
```

- [ ] **Step 2: Remove funding, update issue templates and FREQUENT_ISSUES**

```sh
git rm -q .github/FUNDING.yml
sed -i '' 's/label: Ice Version/label: Lynx Bar Version/' .github/ISSUE_TEMPLATE/bug_report.yml
git grep -n -i "jordanbaird\|\bIce\b" -- .github
```

Change any remaining `Ice` product mention in `.github/ISSUE_TEMPLATE/*` to `Lynx Bar`. Leave
`.github/workflows/lint.yml` as is.

In `FREQUENT_ISSUES.md`:
- Replace the product name "Ice" with "Lynx Bar" in prose and headings, and update the table
  of contents anchors to match the new headings (e.g. `#lynx-bar-removed-an-item`).
- Keep the upstream issue links (`github.com/jordanbaird/Ice/issues/6`, `#26`), but phrase
  them as "tracked upstream in Ice [#6](…) and [#26](…)".
- Replace "Option + click the Ice icon" with "Option + click the Lynx icon", and
  "Update your `Menu Bar Items` in `Ice`" with "Update your `Menu Bar Items` in `Lynx Bar`".

- [ ] **Step 3: Update `CLAUDE.md`**

Make these edits:
- **Project:** say the fork is based on upstream's `macos-26` branch (merged on 2026-10-02),
  and is now Lynx Bar (`com.ikentrock.LynxBar`, product `Lynx Bar.app`). The target, scheme
  and Swift module are still `Ice`, and so are the `//  Ice` file headers, until the internal
  rename (Step 2 spec). Remove the paragraph about upstream bundle ID, team and Sparkle feed;
  replace it with: "Identity and signing live in `Config/Base.xcconfig`. Updates are off
  (no `SUFeedURL`)."
- **Commands:**
  - Build becomes
    `xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Debug build` (signing comes
    from the xcconfig; add `Config/Local.xcconfig` with `CODE_SIGN_IDENTITY = <cert>` to sign
    with a certificate).
  - Add `Scripts/run-tests.sh` (standalone `swiftc` tests; `LYNX_TEST_CERT=<sha1>` also tests
    certificate signing).
  - Note that SPM dependencies are resolved via the project, except CompactSlider, which is
    vendored in `Packages/CompactSlider` (see `VENDORED.md`).
- **Architecture:**
  - Entry is now `Main/AppDelegate.swift` (it runs `IceSettingsImporter`, then creates
    `AppState`, then `MigrationManager.migrateAll()` in `applicationWillFinishLaunching`).
    Migrations are in `Utilities/Migration.swift`.
  - `AppState` owns `settings`, `permissions`, `navigationState`, `menuBarManager`,
    `appearanceManager`, `spacingManager`, `itemManager`, `imageCache`, `hidEventManager`,
    `updatesManager` and `userNotificationManager`.
  - Add a paragraph: "**macOS 26 item identity.** All menu bar item windows are owned by
    Control Center on macOS 26. The `MenuBarItemService` XPC helper
    (`MenuBarItemService/`, code shared via `Shared/`) maps windows to their source apps using
    Accessibility (`SourcePIDCache`). The app and helper trust each other only when signed
    with the same certificate and the expected identifier (`Shared/Services/PeerCodeRequirement.swift`).
    If the helper is refused, `MenuBarItemManager.helperFailureReason` is set and items are
    neither cached nor moved."
  - Update paths: Bridging is in `Shared/Bridging/`, the Lynx Shelf (`IceBar` types) is in
    `MenuBar/IceBar/`, and the layout arranger is in `MenuBar/LayoutBar/`. Verify each path
    you mention with `ls`.
- Add a **Debugging** section:
  - "In zsh `log` is a builtin; use `/usr/bin/log show --predicate 'subsystem == \"com.ikentrock.LynxBar\"'`."
  - "Ad-hoc builds lose Accessibility/Screen Recording grants on every rebuild; sign with a
    certificate."

- [ ] **Step 4: Check for stray upstream references**

```sh
git grep -n -i "jordanbaird" -- . ':!docs' ':!Packages'
```

Expected matches only:
- `AboutSettingsPane.swift` (the upstream link)
- `README.md` (credits)
- `FREQUENT_ISSUES.md` (upstream issue links)
- `CLAUDE.md` (upstream remote and fork origin)
- `IceSettingsImporter.swift` (`com.jordanbaird.Ice`)
- `Ice/Resources/Acknowledgements.*`
- `LICENSE`, if any

- [ ] **Step 5: Commit**

```sh
git add -A README.md FREQUENT_ISSUES.md .github CLAUDE.md
git commit -m "Rewrite repo docs for Lynx Bar

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Full verification and hand-off

**Files:** none changed (fixes found here go back to the owning task's files, as new commits).

- [ ] **Step 1: Clean builds and tests**

```sh
git status --short   # expect: empty
Scripts/run-tests.sh && LYNX_TEST_CERT=E0ED98F7B2D56951B4E0A99082DEBAF25AF66311 Scripts/run-tests.sh
rm -rf ~/Library/Caches/lynx-bar-dev/dd-lynx
xcodebuild -project Ice.xcodeproj -scheme Ice -configuration Release \
  -derivedDataPath ~/Library/Caches/lynx-bar-dev/dd-lynx build 2>&1 | grep -E "error:|BUILD" | sort -u
swiftlint --strict
```

Expected: tests pass in both modes and the Release build succeeds. Lint shows only the
pre-existing `IconResource.swift` violation (out of scope; mention it in the hand-off).

- [ ] **Step 2: Fresh-user run from the Release build**

```sh
pkill -x "Lynx Bar"; sleep 1
defaults delete com.ikentrock.LynxBar 2>/dev/null; true
tccutil reset Accessibility com.ikentrock.LynxBar; tccutil reset ScreenCapture com.ikentrock.LynxBar
rm -rf ~/Applications/"Lynx Bar.app"
cp -R ~/Library/Caches/lynx-bar-dev/dd-lynx/Build/Products/Release/"Lynx Bar.app" ~/Applications/
open ~/Applications/"Lynx Bar.app"
```

Walk the owner through the spec's Testing list, ticking each item:
1. The permissions window says "Lynx Bar". After granting both permissions and relaunching:
   - the Lynx glyph appears, or the owner's imported icon choice
   - the sections match Ice's
   - the Lynx Shelf shows hidden items and clicking one works
   - Menu Bar Layout shows items, and dragging one between sections works
   - search lists items
2. After rebuilding and reinstalling (re-run Step 1's build and the copy), **no** permission
   prompt.
3. About: "Updates are not available in this build."
4. Identity: System Settings → Privacy lists "Lynx Bar"; Activity Monitor shows "Lynx Bar"
   and "MenuBarItemService"; VoiceOver reads "Lynx Bar" on the icon.

Record anything that misbehaves on macOS 26 in the hand-off as "found, not fixed" (spec §8).
Fix it now only if it blocks one of these checks.

- [ ] **Step 3: Clean up spike leftovers (ask the owner first)**

Ask the owner before deleting each of these:
- `~/Applications/IceSpike.app`, `~/Applications/IceMainDebug.app`
- the defaults domains `com.ikentrock.IceSpike` and `com.ikentrock.IceMainDebug`
- `~/Library/Caches/lynx-bar-dev/spike-macos26` (`git worktree remove`)
- the branch `fix/xcode27-and-windowid-crash`

- [ ] **Step 4: Hand off**

Use superpowers:finishing-a-development-branch to merge `lynx-bar-rebrand` into `main`.
Don't push without the owner's go-ahead. Pushing goes to `origin` = `ikentrock/lynx-bar`,
the owner's personal account, which is correct for this repo.
