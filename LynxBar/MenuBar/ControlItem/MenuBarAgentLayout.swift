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
/// a divider that is too wide) has no slot.
@available(macOS 27.0, *)
struct MenuBarAgentLayout {
    /// The bundle identifier of the process that hosts the menu bar.
    static let agentBundleIdentifier = "com.apple.MenuBarAgent"

    /// The Accessibility description of the system's overflow button.
    static let chevronDescription = "Show Hidden Menu Bar Items"

    /// Frames of the slots that belong to Lynx Bar's own status items.
    var ownSlots = [CGRect]()

    /// Frames of every other item's slot.
    var otherSlots = [CGRect]()

    /// The frame of the overflow button, if it's shown.
    var chevron: CGRect?

    /// Reads the current layout, or returns `nil` if the agent can't be read.
    static func current() -> MenuBarAgentLayout? {
        guard
            let agent = NSRunningApplication.runningApplications(withBundleIdentifier: agentBundleIdentifier).first,
            let app = AXHelpers.application(for: agent)
        else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var layout = MenuBarAgentLayout()
        for window in AXHelpers.windows(for: app) {
            for slot in AXHelpers.children(for: window) {
                guard let frame = AXHelpers.frame(for: slot) else {
                    continue
                }
                let element = AXHelpers.children(for: slot).first ?? slot
                if AXHelpers.description(for: element) == chevronDescription {
                    layout.chevron = frame
                } else if AXHelpers.pid(for: element) == ownPID {
                    layout.ownSlots.append(frame)
                } else {
                    layout.otherSlots.append(frame)
                }
            }
        }
        return layout
    }
}
