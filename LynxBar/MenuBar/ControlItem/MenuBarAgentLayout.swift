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
/// by side, hidden or not. Only the window that holds the `«` is read then.
@available(macOS 27.0, *)
struct MenuBarAgentLayout {
    /// The bundle identifier of the process that hosts the menu bar.
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    /// How long to wait for the agent to answer an Accessibility request.
    static let messagingTimeout: Float = 1

    /// Frames of the slots that belong to Lynx Bar's own status items.
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
    static func current() -> MenuBarAgentLayout? {
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
        return layout
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
