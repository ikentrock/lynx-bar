//
//  HostedHidingWidth.swift
//  LynxBar
//

import CoreGraphics

/// Calculations for hiding a section on macOS 27, where the menu bar is
/// hosted by `MenuBarAgent`.
///
/// macOS 27 hides an item only by moving it into its own "Show Hidden Menu
/// Bar Items" overflow when it doesn't fit. A divider hides its section by
/// being just wide enough that the section no longer fits. Too narrow, and the
/// section's leading items stay visible. Too wide, and the system drops the
/// divider itself. It also drops any item wider than half the display.
///
/// Ported from IceMelt (https://github.com/pnikolaidis/icemelt, PR #46), GPL-3.0.
enum HostedHidingWidth {
    /// Space left between the region's start and the hidden items. It must be
    /// narrower than any item, or the section's last item stays in the bar.
    static let margin: CGFloat = 8

    /// The padding `MenuBarAgent` adds around an item's length.
    static let padding: CGFloat = 16

    /// Width changes smaller than this are ignored, since every change
    /// reflows the bar.
    static let threshold: CGFloat = 8

    /// How many times in a row a dropped divider is reset before giving up.
    static let maxResets = 3

    /// Returns where the agent's item area begins: after the application
    /// menu, or after the notch if that's further right.
    static func regionLeft(applicationMenuMaxX: CGFloat, notchMaxX: CGFloat?) -> CGFloat {
        max(applicationMenuMaxX, notchMaxX ?? applicationMenuMaxX) + padding
    }

    /// Returns how wide a divider must be to hide everything between the
    /// region's start and `visibleFrom`.
    static func width(visibleFrom: CGFloat, regionLeft: CGFloat) -> CGFloat {
        max(visibleFrom - regionLeft - margin, 0)
    }

    /// Returns the status item length for a measured width, capped so the
    /// system doesn't drop the divider. With no measurement, uses the cap.
    static func length(width: CGFloat?, screenWidth: CGFloat) -> CGFloat {
        let cap = (screenWidth / 2).rounded(.down) - padding
        guard let width else {
            return cap
        }
        return min(max(width - padding, 0), cap)
    }

    /// Returns whether a new width differs enough from the old one to apply.
    static func shouldApply(old: CGFloat?, new: CGFloat) -> Bool {
        guard let old else {
            return true
        }
        return abs(old - new) >= threshold
    }

    /// Returns where the items that must stay visible begin.
    ///
    /// - Parameters:
    ///   - dividerSlot: The divider's slot in the agent's layout, or `nil` if
    ///     the divider isn't in the bar.
    ///   - otherSlots: Every other item's slot.
    ///   - chevron: The overflow button's frame, if it's shown. Overflowed
    ///     items are listed piled up against it and aren't in the bar.
    static func visibleFrom(dividerSlot: CGRect?, otherSlots: [CGRect], chevron: CGRect?) -> CGFloat? {
        if let dividerSlot {
            return dividerSlot.maxX
        }
        let inBar = otherSlots.filter { slot in
            guard let chevron else {
                return true
            }
            return slot.minX >= chevron.maxX
        }
        return inBar.map(\.minX).min()
    }

    /// Returns the slot that belongs to the status item window with the
    /// given frame. Slots and windows share the x axis.
    static func slot(forWindowFrame windowFrame: CGRect, in ownSlots: [CGRect]) -> CGRect? {
        ownSlots.first { slot in
            abs(slot.minX - windowFrame.minX) <= 2 && abs(slot.width - windowFrame.width) <= 2
        }
    }

    /// Returns whether a dropped divider may be reset again after
    /// `resetCount` resets in a row.
    static func shouldReset(resetCount: Int) -> Bool {
        resetCount < maxResets
    }
}
