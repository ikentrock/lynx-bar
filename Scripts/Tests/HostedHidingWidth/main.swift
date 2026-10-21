//
//  main.swift
//  Tests
//

import CoreGraphics
import Foundation

// MARK: regionLeft

expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 533, notchMaxX: nil) == 549,
    "region starts after the app menu plus the agent's padding"
)
expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 400, notchMaxX: 820) == 836,
    "region starts after the notch when the notch is further right"
)
expect(
    HostedHidingWidth.regionLeft(applicationMenuMaxX: 900, notchMaxX: 820) == 916,
    "region starts after the app menu when it passes the notch"
)

// MARK: width

expect(
    HostedHidingWidth.width(visibleFrom: 1600, regionLeft: 549) == 1043,
    "width is the room less the margin"
)
expect(
    HostedHidingWidth.width(visibleFrom: 555, regionLeft: 549) == 0,
    "room smaller than the margin gives zero"
)
expect(
    HostedHidingWidth.width(visibleFrom: 500, regionLeft: 549) == 0,
    "negative room gives zero"
)

// MARK: length

expect(
    HostedHidingWidth.length(width: 600, screenWidth: 1920) == 584,
    "length is the width less the agent's padding"
)
expect(
    HostedHidingWidth.length(width: 1043, screenWidth: 1920) == 944,
    "length is capped at half the display less the padding"
)
expect(
    HostedHidingWidth.length(width: nil, screenWidth: 1920) == 944,
    "no measurement uses the cap"
)
expect(
    HostedHidingWidth.length(width: 10, screenWidth: 1920) == 0,
    "a width under the padding gives zero, never negative"
)
expect(
    HostedHidingWidth.length(width: 2000, screenWidth: 1801) == 884,
    "the cap rounds half an odd display width down"
)

// MARK: shouldApply

expect(HostedHidingWidth.shouldApply(old: nil, new: 500), "the first measurement is applied")
expect(!HostedHidingWidth.shouldApply(old: 500, new: 507.9), "changes under 8 pt are ignored")
expect(HostedHidingWidth.shouldApply(old: 500, new: 508), "changes of 8 pt are applied")
expect(HostedHidingWidth.shouldApply(old: 500, new: 420), "a shrinking room is applied")

// MARK: slot matching

let ownSlots = [
    CGRect(x: 1564, y: 0, width: 36, height: 30),
    CGRect(x: 1598, y: 0, width: 35, height: 30),
]
expect(
    HostedHidingWidth.slot(forWindowFrame: CGRect(x: 1564, y: 1049, width: 36, height: 33), in: ownSlots)
        == ownSlots[0],
    "a slot matches the window with the same x and width"
)
expect(
    HostedHidingWidth.slot(forWindowFrame: CGRect(x: 684, y: 1049, width: 1016, height: 33), in: ownSlots) == nil,
    "a dropped divider has no slot even though its window claims a place"
)

// MARK: divider state

do {
    var state = HostedHidingWidth.DividerState()
    expect(
        state.update(hasSlot: false, isHiding: false, isCovered: false) == .ignore,
        "a shown divider without a slot isn't measured (review #1)"
    )
    expect(
        state.update(hasSlot: true, isHiding: false, isCovered: false) == .measure,
        "a shown divider with a slot is measured"
    )
}

do {
    var state = HostedHidingWidth.DividerState()
    expect(state.update(hasSlot: false, isHiding: true, isCovered: false) == .reset, "a dropped divider is reset")
    expect(state.isResetting, "a reset divider takes its standard length")
    expect(
        state.update(hasSlot: true, isHiding: true, isCovered: false) == .measureAndVerify,
        "a divider back after a reset is measured and verified again (review #2)"
    )
    expect(!state.isResetting, "the hiding length is applied again after a reset")
    expect(state.update(hasSlot: true, isHiding: true, isCovered: false) == .measure, "a verified divider is measured")
    expect(state.resetCount == 0, "a verified divider re-arms the reset count (review #2)")
}

do {
    var state = HostedHidingWidth.DividerState()
    for _ in 0..<3 {
        _ = state.update(hasSlot: false, isHiding: true, isCovered: false)
        _ = state.update(hasSlot: true, isHiding: true, isCovered: false)
    }
    expect(
        state.update(hasSlot: false, isHiding: true, isCovered: false) == .giveUp,
        "a divider that drops after every reapply gives up after three resets"
    )
    expect(state.isResetting, "a divider that gave up stays at its standard length")
    expect(
        state.update(hasSlot: true, isHiding: true, isCovered: false) == .ignore,
        "a divider that gave up isn't reapplied while hidden"
    )
    expect(
        state.update(hasSlot: true, isHiding: false, isCovered: false) == .measure,
        "showing the section re-arms a divider that gave up (review #2)"
    )
    expect(state.resetCount == 0 && !state.isResetting, "showing clears the reset state")
}

do {
    var state = HostedHidingWidth.DividerState()
    expect(
        state.update(hasSlot: false, isHiding: true, isCovered: true) == .ignore,
        "a divider inside the hidden region is neither reset nor measured (review #3)"
    )
    expect(state.resetCount == 0, "a covered divider spends no resets")
}

// MARK: reset limit

expect(HostedHidingWidth.shouldReset(resetCount: 0), "the first reset is allowed")
expect(HostedHidingWidth.shouldReset(resetCount: 2), "the third reset is allowed")
expect(!HostedHidingWidth.shouldReset(resetCount: 3), "a fourth reset in a row is refused")

// MARK: itemFrames

do {
    let divider = CGRect(x: 872, y: 0, width: 273, height: 24)
    let lynxIcon = CGRect(x: 1185, y: 0, width: 33, height: 24)
    let chevron = CGRect(x: 1128, y: 0, width: 18, height: 24)
    let siri = CGRect(x: 1294, y: 0, width: 32, height: 24)
    let dividerWindow = CGRect(x: 873, y: -33, width: 272, height: 24)
    let frames = HostedHidingWidth.itemFrames(
        ownSlots: [divider, lynxIcon],
        otherSlots: [siri],
        chevron: chevron,
        dividerWindowFrames: [dividerWindow]
    )
    expect(frames.contains(lynxIcon), "the Lynx icon counts as an item")
    expect(frames.contains(siri), "other apps' items count as items")
    expect(frames.contains(chevron), "the « counts as an item")
    expect(!frames.contains(divider), "a divider's slot is empty space, not an item")
    expect(
        HostedHidingWidth.itemFrames(ownSlots: [divider], otherSlots: [], chevron: nil, dividerWindowFrames: []) == [divider],
        "an own slot that matches no divider counts as an item"
    )
}

finishTests("HostedHidingWidth")
