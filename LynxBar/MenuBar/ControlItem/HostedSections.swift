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

    /// One on-screen window, for ``holdsRehide(windows:revealedPIDs:)``.
    struct WindowSummary: Equatable {
        let ownerPID: pid_t
        let layer: Int
    }

    /// Whether rehiding must wait: a revealed app has a window open above
    /// the normal level (a menu, popover or panel). Hiding removes the
    /// app's items, which would close it. Other apps' windows don't count,
    /// so a stray one can't hold rehiding forever.
    static func holdsRehide(windows: [WindowSummary], revealedPIDs: Set<pid_t>) -> Bool {
        guard !revealedPIDs.isEmpty else {
            return false
        }
        return windows.contains { $0.layer > 0 && revealedPIDs.contains($0.ownerPID) }
    }

    /// How our items were found in the item list.
    enum OwnItemMatch: Equatable {
        /// Every window matched its own slot.
        case byFrame
        /// One window didn't match, and the usual order filled it in.
        case byOrder
    }

    /// The list slots of our items, one per entry of `matched`, given in
    /// their usual left-to-right order (always-hidden divider, hidden
    /// divider, Lynx icon). `matched` holds each item's slot as matched by
    /// its window's frame, or `nil`.
    ///
    /// The order fills in at most one unmatched item, and only if it agrees
    /// with every match: the owner may have moved our items. Otherwise this
    /// returns `nil`.
    static func ownItemSlots(
        matched: [CGRect?],
        ownSlots: [CGRect]
    ) -> (slots: [CGRect], match: OwnItemMatch)? {
        guard !matched.isEmpty else {
            return nil
        }
        let found = matched.compactMap { $0 }
        let isDistinct = found.indices.allSatisfy { i in
            !found[..<i].contains(found[i])
        }
        if found.count == matched.count, isDistinct {
            return (found, .byFrame)
        }
        guard
            matched.count(where: { $0 == nil }) <= 1,
            ownSlots.count == matched.count,
            zip(matched, ownSlots).allSatisfy({ match, slot in match.map { $0 == slot } ?? true })
        else {
            return nil
        }
        return (ownSlots, .byOrder)
    }

    /// Whether the app bundle sits directly in /Applications.
    static func isInApplicationsFolder(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.deletingLastPathComponent().path == "/Applications"
    }

    private static func isLeft(_ frame: CGRect, of divider: CGRect) -> Bool {
        frame.maxX <= divider.minX + tolerance
    }
}
