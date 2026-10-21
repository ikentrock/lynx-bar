//
//  SystemOverflow.swift
//  LynxBar
//

import Cocoa
import OSLog

/// Opens and closes the system's overflow (`«`, "Show Hidden Menu Bar Items")
/// on macOS 27, where it takes the place of the Lynx Shelf.
///
/// The `«` has no Accessibility actions, so it's clicked with synthesized
/// mouse events, and the pointer is put back where it was. Once open, the
/// overflow stays open until the `«` is clicked again, wherever the pointer
/// goes.
@available(macOS 27.0, *)
@MainActor
enum SystemOverflow {
    private static let logger = Logger(category: "SystemOverflow")

    /// A Boolean value that indicates whether the overflow is being opened
    /// or closed.
    private(set) static var isChanging = false

    /// A Boolean value that indicates whether the overflow is open.
    static var isExpanded: Bool {
        MenuBarAgentLayout.current()?.isOverflowExpanded ?? false
    }

    /// Opens or closes the overflow so that it matches `expanded`.
    ///
    /// - Returns: `true` if the overflow is now in the requested state.
    @discardableResult
    static func setExpanded(_ expanded: Bool, hidEventManager: HIDEventManager) async -> Bool {
        guard let layout = MenuBarAgentLayout.current() else {
            logger.error("Can't read MenuBarAgent's layout")
            return false
        }
        guard layout.isOverflowExpanded != expanded else {
            return true
        }
        guard let chevron = layout.chevron else {
            // Nothing is overflowed, so there's nothing to open.
            return !expanded
        }
        isChanging = true
        defer {
            isChanging = false
        }
        // The Lynx icon acts on mouse down, so the user's button may still
        // be pressed. A click posted before it's released is lost.
        for _ in 0..<40 where MouseHelpers.isButtonPressed() {
            try? await Task.sleep(for: .milliseconds(25))
        }
        await click(at: HostedOverflow.clickPoint(chevron: chevron), hidEventManager: hidEventManager)
        let isExpanded = isExpanded
        logger.debug("Clicked the overflow button to \(expanded ? "open" : "close", privacy: .public) it; open: \(isExpanded, privacy: .public)")
        return isExpanded == expanded
    }

    /// Clicks at the given point and puts the pointer back.
    private static func click(at point: CGPoint, hidEventManager: HIDEventManager) async {
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let savedLocation = MouseHelpers.locationCoreGraphics
        else {
            logger.error("Can't create the events to click the overflow button")
            return
        }

        // Lynx Bar's own event monitors would treat the click as the user's.
        hidEventManager.stopAll()
        MouseHelpers.hideCursor()

        for type: CGEventType in [.mouseMoved, .leftMouseDown, .leftMouseUp] {
            CGEvent(
                mouseEventSource: source,
                mouseType: type,
                mouseCursorPosition: point,
                mouseButton: .left
            )?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(50))
        }

        MouseHelpers.warpCursor(to: savedLocation)
        MouseHelpers.showCursor()
        try? await Task.sleep(for: .milliseconds(150))
        hidEventManager.startAll()
    }
}
