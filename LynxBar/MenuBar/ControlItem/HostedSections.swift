//
//  HostedSections.swift
//  LynxBar
//

import CoreGraphics
import Foundation

/// One item in MenuBarAgent's item-list window, left to right.
struct HostedItem: Equatable {
    let bundleIdentifier: String?
    let frame: CGRect
    let isOwn: Bool
}

/// The apps the owner put in each hiding section.
struct HostedSectionSets: Equatable {
    var hidden: Set<String> = []
    var alwaysHidden: Set<String> = []
}

/// Decides which apps macOS 27 hides, from where their icons sit relative to
/// the dividers. Pure logic, so it can be tested without the menu bar.
enum HostedSections {
    /// How far right of a divider's left edge an item may end and still count
    /// as left of it.
    private static let tolerance: CGFloat = 2

    /// Whether an app may be put in a hidden set.
    static func isHideable(_ bundleIdentifier: String, ownBundleIdentifier: String) -> Bool {
        !bundleIdentifier.hasPrefix("com.apple.") && bundleIdentifier != ownBundleIdentifier
    }

    /// Reassigns every hideable app seen in `items` by its leftmost icon.
    /// An app left of the always-hidden divider goes to always-hidden; left
    /// of the hidden divider, to hidden; otherwise to neither. Apps not seen
    /// keep their membership. A nil divider means that section is off.
    static func updatedSets(
        _ stored: HostedSectionSets,
        items: [HostedItem],
        hiddenDivider: CGRect?,
        alwaysHiddenDivider: CGRect?,
        ownBundleIdentifier: String
    ) -> HostedSectionSets {
        var leftmost = [String: CGRect]()
        for item in items where !item.isOwn {
            guard
                let id = item.bundleIdentifier,
                isHideable(id, ownBundleIdentifier: ownBundleIdentifier)
            else {
                continue
            }
            if let current = leftmost[id], current.minX <= item.frame.minX {
                continue
            }
            leftmost[id] = item.frame
        }

        var sets = stored
        for (id, frame) in leftmost {
            sets.hidden.remove(id)
            sets.alwaysHidden.remove(id)
            if let divider = alwaysHiddenDivider, isLeft(frame, of: divider) {
                sets.alwaysHidden.insert(id)
            } else if let divider = hiddenDivider, isLeft(frame, of: divider) {
                sets.hidden.insert(id)
            }
        }
        return sets
    }

    /// The bundle identifiers to allow: `candidates`, minus the sets of the
    /// hidden sections, plus our own. Sorted, so equal inputs give equal output.
    static func allowlist(
        sets: HostedSectionSets,
        hidesHidden: Bool,
        hidesAlwaysHidden: Bool,
        candidates: Set<String>,
        ownBundleIdentifier: String
    ) -> [String] {
        var allowed = candidates
        if hidesHidden {
            allowed.subtract(sets.hidden)
        }
        if hidesAlwaysHidden {
            allowed.subtract(sets.alwaysHidden)
        }
        allowed.insert(ownBundleIdentifier)
        return allowed.sorted()
    }

    /// The live slot of the Lynx icon: our own slot that matches no divider
    /// window (by `HostedHidingWidth.slot(forWindowFrame:in:)`'s rule: same
    /// width ±2, nearest x).
    static func lynxIconSlot(ownSlots: [CGRect], dividerWindowFrames: [CGRect]) -> CGRect? {
        let dividerSlots = dividerWindowFrames.compactMap {
            HostedHidingWidth.slot(forWindowFrame: $0, in: ownSlots)
        }
        return ownSlots.first { !dividerSlots.contains($0) }
    }

    /// Whether the app bundle sits directly in /Applications.
    static func isInApplicationsFolder(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.deletingLastPathComponent().path == "/Applications"
    }

    private static func isLeft(_ frame: CGRect, of divider: CGRect) -> Bool {
        frame.maxX <= divider.minX + tolerance
    }
}
