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

// MARK: visibleFrom

let divider = CGRect(x: 684, y: 0, width: 916, height: 30)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: divider, otherSlots: [], chevron: nil) == 1600,
    "a divider in the bar bounds the visible items with its right edge"
)
let piledUp = [
    CGRect(x: 562, y: 0, width: 38, height: 30),
    CGRect(x: 553, y: 0, width: 47, height: 30),
]
let onBar = [
    CGRect(x: 608, y: 0, width: 36, height: 30),
    CGRect(x: 1600, y: 0, width: 32, height: 30),
]
let chevron = CGRect(x: 583, y: 1, width: 18, height: 28)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: piledUp + onBar, chevron: chevron) == 608,
    "without a divider slot, the leftmost item right of the chevron bounds the room"
)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: onBar, chevron: nil) == 608,
    "without a chevron, every item counts"
)
expect(
    HostedHidingWidth.visibleFrom(dividerSlot: nil, otherSlots: [], chevron: nil) == nil,
    "an empty bar can't be measured"
)

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

// MARK: reset limit

expect(HostedHidingWidth.shouldReset(resetCount: 0), "the first reset is allowed")
expect(HostedHidingWidth.shouldReset(resetCount: 2), "the third reset is allowed")
expect(!HostedHidingWidth.shouldReset(resetCount: 3), "a fourth reset in a row is refused")

finishTests("HostedHidingWidth")
