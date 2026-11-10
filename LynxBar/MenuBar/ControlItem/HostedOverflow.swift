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
/// them out side by side to its left, over the app menu.
///
/// On macOS 27.0 the `«` has no identifier and can only be clicked. From
/// macOS 27.2 it's a button that names its state in its identifier and can be
/// pressed through Accessibility. 27.2 also adds a second agent window that
/// lists every item side by side, hidden or not, and has no `«`.
enum HostedOverflow {
    /// How far two slots may overlap and still count as side by side.
    static let overlapTolerance: CGFloat = 4

    /// The identifier of the `«` while the overflow is closed (macOS 27.2).
    static let collapsedIdentifier = "menu-bar-overflow-indicator"

    /// The identifier of the `«` while the overflow is open (macOS 27.2).
    static let expandedIdentifier = "menu-bar-overflow-indicator-expanded"

    /// Returns whether the `«` with the given identifier says the overflow
    /// is open, or `nil` if the identifier isn't one of the `«`'s.
    static func isExpanded(indicatorIdentifier identifier: String?) -> Bool? {
        switch identifier {
        case collapsedIdentifier: false
        case expandedIdentifier: true
        default: nil
        }
    }

    /// Returns the index of the window that shows the live bar, given the
    /// identifiers of each window's slots, or `nil` to read every window.
    ///
    /// The live bar is the window that holds the `«`. With no identified `«`
    /// (macOS 27.0, or nothing overflowed), every window is read.
    static func liveWindowIndex(slotIdentifiers: [[String?]]) -> Int? {
        slotIdentifiers.firstIndex { identifiers in
            identifiers.contains { isExpanded(indicatorIdentifier: $0) != nil }
        }
    }

    /// Returns a Boolean value that indicates whether the overflow is open.
    ///
    /// The `«`'s identifier decides when it has one. Otherwise, the overflow
    /// is open when at least one item lies entirely left of the `«` without
    /// overlapping any other slot.
    static func isExpanded(
        indicatorIdentifier: String?,
        chevron: CGRect?,
        ownSlots: [CGRect],
        otherSlots: [CGRect]
    ) -> Bool {
        if let isExpanded = isExpanded(indicatorIdentifier: indicatorIdentifier) {
            return isExpanded
        }
        return isExpanded(chevron: chevron, ownSlots: ownSlots, otherSlots: otherSlots)
    }

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
