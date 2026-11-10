//
//  MenuBarAgentLayout.swift
//  LynxBar
//

import AXSwift
import Cocoa

/// The status item layout of `MenuBarAgent`, which hosts the menu bar's
/// status items on macOS 27.
///
/// The agent's Accessibility window has one slot per item. A slot's child
/// element belongs to the process that created the item, which is how Lynx
/// Bar finds its own control items. An item the system dropped (for example,
/// a divider that is too wide) has no slot. The system's overflow button
/// (`«`) is the one slot without a child element.
///
/// From macOS 27.2 the agent has a second window that lists every item side
/// by side. The slots come from the window that holds the `«`, or from both
/// windows when there's no `«`. `listItems` comes from the item-list window:
/// the one without the `«`, or, with no `«`, the one whose own slots match
/// the most of our item windows. Under an allowlist assertion, hidden apps
/// are absent from both windows.
@available(macOS 27.0, *)
struct MenuBarAgentLayout {
    /// The bundle identifier of the process that hosts the menu bar.
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    /// How long to wait for the agent to answer an Accessibility request.
    static let messagingTimeout: Float = 1

    /// Frames of the slots that belong to Lynx Bar's own status items, read
    /// from the live window (the one holding the `«`), or from both windows
    /// when there's no `«`.
    var ownSlots = [CGRect]()

    /// Frames of every other item's slot.
    var otherSlots = [CGRect]()

    /// The frame of the overflow button, if it's shown.
    var chevron: CGRect?

    /// The overflow button's element, if it's shown.
    var chevronElement: UIElement?

    /// The overflow button's identifier, which names its state from macOS
    /// 27.2 on.
    var chevronIdentifier: String?

    /// Every item of the agent's item-list window, left to right.
    var listItems = [HostedItem]()

    /// The index of the agent window `listItems` was read from, and how it
    /// was chosen, for logging.
    var listWindowChoice: (index: Int, reason: String)?

    /// A Boolean value that indicates whether the system's overflow is open.
    var isOverflowExpanded: Bool {
        HostedOverflow.isExpanded(
            indicatorIdentifier: chevronIdentifier,
            chevron: chevron,
            ownSlots: ownSlots,
            otherSlots: otherSlots
        )
    }

    /// One slot of an agent window.
    private enum Slot {
        case item(frame: CGRect, element: UIElement)
        case chevron(frame: CGRect, element: UIElement, identifier: String?)
    }

    /// Reads the current layout, or returns `nil` if the agent can't be read.
    ///
    /// - Parameter ownWindowFrames: The frames of Lynx Bar's status item
    ///   windows. With no `«` to tell the windows apart, the item-list window
    ///   is the one whose own slots match the most of these frames, by
    ///   ``HostedHidingWidth/slot(forWindowFrame:in:)``. The windows differ:
    ///   a divider can have another width in each, and our windows follow
    ///   only one of them.
    static func current(ownWindowFrames: [CGRect] = []) -> MenuBarAgentLayout? {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleIdentifier).first,
            let app = AXHelpers.application(for: agent)
        else {
            return nil
        }
        app.messagingTimeout = messagingTimeout

        let windows = AXHelpers.windows(for: app).map(readSlots)
        let liveIndex = HostedOverflow.liveWindowIndex(slotIdentifiers: windows.map { slots in
            slots.map { slot in
                if case let .chevron(_, _, identifier) = slot { identifier } else { nil }
            }
        })
        let liveWindows = liveIndex.map { [windows[$0]] } ?? windows

        let ownPID = ProcessInfo.processInfo.processIdentifier
        var layout = MenuBarAgentLayout()
        for slot in liveWindows.joined() {
            switch slot {
            case let .item(frame, element):
                if AXHelpers.pid(for: element) == ownPID {
                    layout.ownSlots.append(frame)
                } else {
                    layout.otherSlots.append(frame)
                }
            case let .chevron(frame, element, identifier):
                layout.chevron = frame
                layout.chevronElement = element
                layout.chevronIdentifier = identifier
            }
        }

        let listIndex: Int?
        if let liveIndex {
            listIndex = windows.indices.first { $0 != liveIndex }
            layout.listWindowChoice = listIndex.map { ($0, "the window without the «") }
        } else if
            !ownWindowFrames.isEmpty,
            let best = bestMatchingWindow(windows, ownWindowFrames: ownWindowFrames, ownPID: ownPID)
        {
            listIndex = best
            layout.listWindowChoice = (best, "most of our windows matched")
        } else {
            listIndex = windows.indices.first
            layout.listWindowChoice = listIndex.map { ($0, "the first window") }
        }
        if let listIndex {
            layout.listItems = windows[listIndex].compactMap { slot in
                guard case let .item(frame, element) = slot else {
                    return nil
                }
                let pid = AXHelpers.pid(for: element)
                return HostedItem(
                    bundleIdentifier: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                    frame: frame,
                    isOwn: pid == ownPID
                )
            }
            .sorted { $0.frame.minX < $1.frame.minX }
        }
        return layout
    }

    /// The index of the window whose own slots match the most of our window
    /// frames, or `nil` if no window matches more than the others.
    private static func bestMatchingWindow(
        _ windows: [[Slot]],
        ownWindowFrames: [CGRect],
        ownPID: pid_t
    ) -> Int? {
        let counts = windows.map { slots in
            let ownSlots = slots.compactMap { slot -> CGRect? in
                guard case let .item(frame, element) = slot, AXHelpers.pid(for: element) == ownPID else {
                    return nil
                }
                return frame
            }
            return ownWindowFrames.count { HostedHidingWidth.slot(forWindowFrame: $0, in: ownSlots) != nil }
        }
        guard
            let best = counts.indices.max(by: { counts[$0] < counts[$1] }),
            counts[best] > 0,
            counts.filter({ $0 == counts[best] }).count == 1
        else {
            return nil
        }
        return best
    }

    /// Reads the slots of one agent window.
    private static func readSlots(of window: UIElement) -> [Slot] {
        AXHelpers.children(for: window).compactMap { slot in
            guard let frame = AXHelpers.frame(for: slot) else {
                return nil
            }
            // Only the agent's own elements are asked anything, so an item
            // whose app hangs can't stall the read.
            guard let element = AXHelpers.children(for: slot).first else {
                return .chevron(frame: frame, element: slot, identifier: AXHelpers.identifier(for: slot))
            }
            return .item(frame: frame, element: element)
        }
    }
}
