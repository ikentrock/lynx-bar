//
//  main.swift
//  Tests
//

import CoreGraphics
import Foundation

func slot(_ x: CGFloat, _ width: CGFloat) -> CGRect {
    CGRect(x: x, y: 0, width: width, height: 24)
}

// Measured on macOS 27.0.1 with the hidden section hidden: overflowed items
// are piled up against the « and under the hidden divider.
let collapsedChevron = slot(1128, 18)
let collapsedOwn = [slot(872, 273), slot(1185, 33)]
let collapsedOther = [
    slot(1103, 42), slot(1105, 40), slot(1107, 38), slot(1109, 36), slot(1109, 36),
    slot(1113, 32), slot(1114, 31), slot(1153, 32), slot(1226, 22), slot(1264, 22),
    slot(1294, 32), slot(1334, 26), slot(1376, 116),
]

// The same bar after clicking the «: hidden items are laid out side by side
// to the left of it, and the hidden divider shrinks to a point.
let expandedChevron = slot(872, 18)
let expandedOwn = [slot(1152, 1), slot(1185, 33)]
let expandedOther = [
    slot(374, 38), slot(412, 47), slot(460, 66), slot(526, 47), slot(572, 71),
    slot(897, 42), slot(939, 36), slot(975, 40), slot(1015, 36), slot(1051, 32),
    slot(1083, 38), slot(1121, 31), slot(1153, 32), slot(1226, 22), slot(1264, 22),
    slot(1294, 32), slot(1334, 26), slot(1376, 116),
]

expect(
    !HostedOverflow.isExpanded(chevron: collapsedChevron, ownSlots: collapsedOwn, otherSlots: collapsedOther),
    "items piled up against the « mean the overflow is closed"
)
expect(
    HostedOverflow.isExpanded(chevron: expandedChevron, ownSlots: expandedOwn, otherSlots: expandedOther),
    "items laid out side by side left of the « mean the overflow is open"
)
expect(
    !HostedOverflow.isExpanded(chevron: nil, ownSlots: collapsedOwn, otherSlots: expandedOther),
    "without a « nothing is overflowed"
)
expect(
    !HostedOverflow.isExpanded(chevron: slot(1128, 18), ownSlots: [slot(1080, 65)], otherSlots: [slot(1112, 33)]),
    "a single overflowed item under the divider means the overflow is closed"
)
expect(
    !HostedOverflow.isExpanded(chevron: slot(300, 18), ownSlots: [], otherSlots: [slot(400, 30), slot(430, 30)]),
    "items right of the « are on the bar, not in an open overflow"
)
expect(
    HostedOverflow.clickPoint(chevron: slot(1128, 18)) == CGPoint(x: 1137, y: 12),
    "the « is clicked at its centre"
)

finishTests("HostedOverflow")
