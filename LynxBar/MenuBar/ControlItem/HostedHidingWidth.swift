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

    /// What to do with a divider after reading the agent's layout.
    enum DividerAction: Equatable {
        /// Leave the divider and its width alone.
        case ignore
        /// Measure the room from the divider's slot.
        case measure
        /// Measure, then measure again later to check the applied width.
        case measureAndVerify
        /// Give the divider its standard length so it returns to the bar.
        case reset
        /// Stop resetting; the divider keeps dropping out of the bar.
        case giveUp
    }

    /// The reset state of one divider.
    ///
    /// A divider the system drops while hiding is reset to its standard
    /// length, then measured and verified once it's back. Showing the
    /// section re-arms it.
    struct DividerState: Equatable {
        /// Resets in a row without a verified hiding width.
        private(set) var resetCount = 0

        /// Whether the divider must take its standard length.
        private(set) var isResetting = false

        /// Whether resetting stopped until the section is shown again.
        private(set) var hasGivenUp = false

        /// Updates the state from a layout reading and returns what to do.
        ///
        /// - Parameters:
        ///   - hasSlot: Whether the divider has a slot in the agent's layout.
        ///   - isHiding: Whether the divider's section is hidden.
        ///   - isCovered: Whether the divider is inside another hidden
        ///     section's region, so its slot says nothing about its room.
        mutating func update(hasSlot: Bool, isHiding: Bool, isCovered: Bool) -> DividerAction {
            guard isHiding else {
                self = DividerState()
                return hasSlot ? .measure : .ignore
            }
            if isCovered || hasGivenUp {
                return .ignore
            }
            guard hasSlot else {
                guard shouldReset(resetCount: resetCount) else {
                    hasGivenUp = true
                    isResetting = true
                    return .giveUp
                }
                resetCount += 1
                isResetting = true
                return .reset
            }
            if isResetting {
                isResetting = false
                return .measureAndVerify
            }
            resetCount = 0
            return .measure
        }
    }
}
