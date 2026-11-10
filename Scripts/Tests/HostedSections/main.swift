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

// Measured on 27.2: Lynx icon 33 pt, hidden divider 16 pt; windows sit 56 pt right of the live slots.
expect(
    HostedSections.lynxIconSlot(
        ownSlots: [CGRect(x: 1098, y: 0, width: 33, height: 30), CGRect(x: 1347, y: 0, width: 16, height: 30)],
        dividerWindowFrames: [CGRect(x: 1403, y: 1050, width: 16, height: 30)]
    ) == CGRect(x: 1098, y: 0, width: 33, height: 30),
    "the Lynx icon is the own slot that matches no divider"
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

expect(HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Lynx Bar.app")), "/Applications counts")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Users/x/Applications/Lynx Bar.app")), "~/Applications doesn't")
expect(!HostedSections.isInApplicationsFolder(URL(fileURLWithPath: "/Applications/Tools/Lynx Bar.app")), "a subfolder doesn't")

finishTests("HostedSections")
