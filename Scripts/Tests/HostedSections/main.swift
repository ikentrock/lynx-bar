//
//  main.swift
//  Tests
//

import CoreGraphics
import Foundation

let own = "com.ikentrock.LynxBar"
let hiddenDivider = CGRect(x: 567, y: 0, width: 16, height: 30)
let alwaysHiddenDivider = CGRect(x: 200, y: 0, width: 16, height: 30)

func item(_ id: String?, _ x: CGFloat, own: Bool = false) -> HostedItem {
    HostedItem(bundleIdentifier: id, frame: CGRect(x: x, y: 0, width: 30, height: 30), isOwn: own)
}

expect(!HostedSections.isHideable("com.apple.controlcenter", ownBundleIdentifier: own), "Apple items are never hideable")
expect(!HostedSections.isHideable(own, ownBundleIdentifier: own), "Lynx Bar is never hideable")
expect(HostedSections.isHideable("com.microsoft.teams2", ownBundleIdentifier: own), "other apps are hideable")

let items = [
    item("chat.rocket", 100), item("com.electron.ollama", 300), item("com.microsoft.teams2", 400),
    item(own, 450, own: true), item("com.tinyspeck.slackmacgap", 700), item(nil, 750),
    item("com.apple.weather.menu", 320),
]
let sets = HostedSections.updatedSets(
    .init(), items: items, hiddenDivider: hiddenDivider,
    alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(
    sets.hidden == ["chat.rocket", "com.electron.ollama", "com.microsoft.teams2"],
    "apps left of the hidden divider are hidden"
)
expect(sets.alwaysHidden.isEmpty, "no always-hidden divider, no always-hidden apps")

let withAH = HostedSections.updatedSets(
    .init(), items: items, hiddenDivider: hiddenDivider,
    alwaysHiddenDivider: alwaysHiddenDivider, ownBundleIdentifier: own
)
expect(
    withAH.alwaysHidden == ["chat.rocket"] && !withAH.hidden.contains("chat.rocket"),
    "left of the always-hidden divider is always-hidden only"
)
expect(
    withAH.hidden == ["com.electron.ollama", "com.microsoft.teams2"],
    "between the dividers is hidden"
)

let toHidden = HostedSections.updatedSets(
    .init(alwaysHidden: ["com.microsoft.teams2"]), items: [item("com.microsoft.teams2", 400)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysHiddenDivider, ownBundleIdentifier: own
)
expect(
    toHidden.hidden == ["com.microsoft.teams2"] && toHidden.alwaysHidden.isEmpty,
    "an always-hidden app seen between the dividers moves to hidden"
)
let toNeither = HostedSections.updatedSets(
    .init(hidden: ["com.electron.ollama"], alwaysHidden: ["chat.rocket"]),
    items: [item("com.electron.ollama", 800), item("chat.rocket", 900)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: alwaysHiddenDivider, ownBundleIdentifier: own
)
expect(
    toNeither.hidden.isEmpty && toNeither.alwaysHidden.isEmpty,
    "hidden and always-hidden apps seen right of both dividers leave their sets"
)

// Items are 30 pt wide and the hidden divider starts at 567: an item may end 2 pt into it.
let atTolerance = HostedSections.updatedSets(
    .init(), items: [item("com.electron.ollama", 539)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(atTolerance.hidden == ["com.electron.ollama"], "ending at the divider's minX + 2 is left of it")
let pastTolerance = HostedSections.updatedSets(
    .init(), items: [item("com.electron.ollama", 539.01)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(pastTolerance.hidden.isEmpty, "ending past the divider's minX + 2 isn't left of it")

let split = HostedSections.updatedSets(
    .init(), items: [item("eu.exelban.Stats", 500), item("eu.exelban.Stats", 900)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(split.hidden == ["eu.exelban.Stats"], "an app with icons on both sides goes to the leftmost section")

let kept = HostedSections.updatedSets(
    .init(hidden: ["com.microsoft.teams2"]), items: [item("com.tinyspeck.slackmacgap", 700)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(kept.hidden == ["com.microsoft.teams2"], "an app that isn't drawn keeps its membership")

let moved = HostedSections.updatedSets(
    .init(hidden: ["com.microsoft.teams2"]), items: [item("com.microsoft.teams2", 800)],
    hiddenDivider: hiddenDivider, alwaysHiddenDivider: nil, ownBundleIdentifier: own
)
expect(moved.hidden.isEmpty, "an app seen right of the divider leaves the hidden set")

let candidates: Set = ["chat.rocket", "com.microsoft.teams2", "com.tinyspeck.slackmacgap", own]
let state = HostedSectionSets(hidden: ["com.microsoft.teams2"], alwaysHidden: ["chat.rocket"])
expect(
    HostedSections.allowlist(
        sets: state, hidesHidden: true, hidesAlwaysHidden: true,
        candidates: candidates, ownBundleIdentifier: own
    ) == ["com.ikentrock.LynxBar", "com.tinyspeck.slackmacgap"],
    "hiding both sections excludes both sets"
)
expect(
    HostedSections.allowlist(
        sets: state, hidesHidden: false, hidesAlwaysHidden: true,
        candidates: candidates, ownBundleIdentifier: own
    ) == ["com.ikentrock.LynxBar", "com.microsoft.teams2", "com.tinyspeck.slackmacgap"],
    "showing hidden keeps always-hidden excluded"
)
expect(
    HostedSections.allowlist(
        sets: .init(hidden: [own]), hidesHidden: true, hidesAlwaysHidden: false,
        candidates: [], ownBundleIdentifier: own
    ) == [own],
    "our own bundle ID is always allowed"
)

// Our items in the list, in their usual order: always-hidden divider, hidden divider, Lynx icon.
let ahSlot = CGRect(x: 1300, y: 0, width: 16, height: 30)
let hSlot = CGRect(x: 1371, y: 0, width: 16, height: 30)
let iconSlot = CGRect(x: 1636, y: 0, width: 33, height: 30)
let allMatched = HostedSections.ownItemSlots(matched: [ahSlot, hSlot, iconSlot], ownSlots: [ahSlot, hSlot, iconSlot])
expect(allMatched?.slots == [ahSlot, hSlot, iconSlot] && allMatched?.match == .byFrame, "all matched: by frame")
let swapped = HostedSections.ownItemSlots(matched: [hSlot, ahSlot, iconSlot], ownSlots: [ahSlot, hSlot, iconSlot])
expect(swapped?.slots == [hSlot, ahSlot, iconSlot] && swapped?.match == .byFrame, "moved items keep their frame matches")
expect(
    HostedSections.ownItemSlots(matched: [nil, nil], ownSlots: [iconSlot, hSlot]) == nil,
    "nothing matched: nil, not the order"
)
let oneUnmatched = HostedSections.ownItemSlots(matched: [nil, iconSlot], ownSlots: [hSlot, iconSlot])
expect(oneUnmatched?.slots == [hSlot, iconSlot] && oneUnmatched?.match == .byOrder, "one unmatched: the order fills it in")
expect(
    HostedSections.ownItemSlots(matched: [nil, nil, iconSlot], ownSlots: [hSlot, ahSlot, iconSlot]) == nil,
    "two unmatched: nil"
)
expect(
    HostedSections.ownItemSlots(matched: [nil, hSlot], ownSlots: [hSlot, iconSlot]) == nil,
    "the order must agree with the matches"
)
expect(
    HostedSections.ownItemSlots(matched: [nil, iconSlot], ownSlots: [hSlot, ahSlot, iconSlot]) == nil,
    "the order needs one list item per section"
)
expect(
    HostedSections.ownItemSlots(matched: [hSlot, hSlot, iconSlot], ownSlots: [ahSlot, hSlot, iconSlot]) == nil,
    "two items matched to the same slot: nil"
)
expect(
    HostedSections.ownItemSlots(matched: [nil, hSlot, hSlot], ownSlots: [ahSlot, hSlot, iconSlot]) == nil,
    "a duplicate match with one unmatched: nil"
)

// Rehiding waits for windows above the normal level of the revealed apps only.
func window(_ pid: pid_t, _ layer: Int) -> HostedSections.WindowSummary {
    HostedSections.WindowSummary(ownerPID: pid, layer: layer)
}
let revealedPIDs: Set<pid_t> = [1722, 1801]
expect(HostedSections.holdsRehide(windows: [window(1722, 101)], revealedPIDs: revealedPIDs), "a revealed app's menu holds")
expect(HostedSections.holdsRehide(windows: [window(1801, 3)], revealedPIDs: revealedPIDs), "a revealed app's panel holds")
expect(HostedSections.holdsRehide(windows: [window(1801, 25)], revealedPIDs: revealedPIDs), "a revealed app's popover holds")
expect(
    !HostedSections.holdsRehide(windows: [window(1722, 0)], revealedPIDs: revealedPIDs),
    "a revealed app's normal window doesn't hold"
)
expect(
    !HostedSections.holdsRehide(windows: [window(764, 20), window(999, 101)], revealedPIDs: revealedPIDs),
    "other apps' windows, even at the menu level, don't hold"
)
expect(!HostedSections.holdsRehide(windows: [window(1722, 101)], revealedPIDs: []), "nothing revealed: no hold")

expect(HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Lynx Bar.app")), "/Applications counts")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Applications/Lynx Bar.app")), "~/Applications doesn't")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tools/Lynx Bar.app")), "a subfolder doesn't")

finishTests("HostedSections")
