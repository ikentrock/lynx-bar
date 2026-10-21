//
//  HostedOverflow.swift
//  LynxBar
//

import CoreGraphics

/// Calculations for the system's overflow button (`«`, "Show Hidden Menu Bar
/// Items") on macOS 27, which Lynx Bar opens in place of the Lynx Shelf.
///
/// While the overflow is closed, the items it holds are piled up against the
/// `«`, overlapping each other and the hidden divider. Clicking the `«` lays
/// them out side by side to its left, over the app menu. The `«` can't be
/// pressed through Accessibility, only clicked.
enum HostedOverflow {
    /// How far two slots may overlap and still count as side by side.
    static let overlapTolerance: CGFloat = 4

    /// Returns a Boolean value that indicates whether the overflow is open,
    /// given the slots of `MenuBarAgent`'s layout.
    ///
    /// The overflow is open when at least one item lies entirely left of the
    /// `«` without overlapping any other slot.
    static func isExpanded(chevron: CGRect?, ownSlots: [CGRect], otherSlots: [CGRect]) -> Bool {
        guard let chevron else {
            return false
        }
        let slots = ownSlots + otherSlots + [chevron]
        return otherSlots.indices.contains { index in
            let item = otherSlots[index]
            guard item.maxX <= chevron.minX else {
                return false
            }
            var others = slots
            others.remove(at: ownSlots.count + index)
            return !others.contains { overlap(item, $0) > overlapTolerance }
        }
    }

    /// Returns the point to click to open or close the overflow.
    static func clickPoint(chevron: CGRect) -> CGPoint {
        CGPoint(x: chevron.midX, y: chevron.midY)
    }

    /// Returns how far two slots overlap horizontally.
    private static func overlap(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX)
    }
}
