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

    /// A Boolean value that indicates whether the system's overflow is open.
    var isOverflowExpanded: Bool {
        HostedOverflow.isExpanded(chevron: chevron, ownSlots: ownSlots, otherSlots: otherSlots)
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
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var layout = MenuBarAgentLayout()
        for window in AXHelpers.windows(for: app) {
            for slot in AXHelpers.children(for: window) {
                guard let frame = AXHelpers.frame(for: slot) else {
                    continue
                }
                // Only the agent's own elements are asked anything, so an item
                // whose app hangs can't stall the read.
                guard let element = AXHelpers.children(for: slot).first else {
                    layout.chevron = frame
                    continue
                }
                if AXHelpers.pid(for: element) == ownPID {
                    layout.ownSlots.append(frame)
                } else {
                    layout.otherSlots.append(frame)
                }
            }
        }
        return layout
    }
}
