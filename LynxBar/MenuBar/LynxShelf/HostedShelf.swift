//
//  HostedShelf.swift
//  LynxBar
//

import AXSwift
import Cocoa
import OSLog

/// The Lynx Shelf's icons on macOS 27.
///
/// MenuBarAgent draws every status item, and the allowlist keeps hidden
/// apps out of it altogether. To show their icons, the shelf draws them in
/// the bar for a moment (a temporary reveal), captures the agent's window,
/// crops each icon by its Accessibility frame, and hides them again. To
/// click one, it reveals that app alone, presses its icon through
/// Accessibility, and hides it again once its menu closes.
@available(macOS 27.0, *)
@MainActor
final class HostedShelf: ObservableObject {
    /// One icon shown in the shelf.
    struct Icon: Identifiable {
        let entry: HostedShelfEntry
        /// The icon as the agent drew it, or `nil` if it wasn't drawn where
        /// it could be captured (for example, behind the `«`).
        let image: NSImage?
        /// The app's own icon, shown in place of a missing `image`.
        let appIcon: NSImage?
        let displayName: String

        var id: HostedShelfEntry { entry }
    }

    /// What the shelf has to show.
    enum State: Equatable {
        case idle
        case loading
        case ready
        case failed
    }

    private static let logger = Logger(category: "HostedShelf")

    /// How long to wait for the revealed apps to be drawn.
    private static let drawTimeout: Duration = .milliseconds(1500)

    /// How long the drawn apps must stay the same before the bar counts as
    /// settled when some apps aren't drawn (they may own no icon).
    private static let minimumDrawWait: Duration = .milliseconds(300)

    /// How long to let the agent finish drawing once its items are listed.
    private static let renderDelay: Duration = .milliseconds(120)

    /// How long to wait for a pressed icon's menu or panel to appear
    /// before clicking it instead.
    private static let pressGrace: Duration = .milliseconds(700)

    /// How long to wait for a clicked icon's menu or panel to appear.
    private static let menuGrace: Duration = .milliseconds(1500)

    /// How long a pressed app can stay revealed while its menu is open.
    private static let menuTimeout: Duration = .seconds(600)

    /// How long to wait for an app to take a press, so a hung app can't
    /// stall the main thread.
    private static let pressTimeout: Float = 0.5

    @Published private(set) var icons = [Icon]()
    @Published private(set) var state = State.idle

    /// One status item in an agent window.
    private struct AgentIcon {
        let bundleIdentifier: String?
        let pid: pid_t?
        let frame: CGRect
        let isOwn: Bool
        /// The agent's slot, which has its own press action.
        let slot: UIElement
        /// The element of the app that owns the item.
        let element: UIElement
    }

    /// One of the agent's Accessibility windows.
    private struct AgentWindow {
        let icons: [AgentIcon]
        /// The identifiers of the slots without an element: the `«`.
        let indicatorIdentifiers: [String?]
    }

    // MARK: Refreshing

    /// Captures the icons of `section`'s apps.
    func refresh(section: MenuBarSection.Name, appState: AppState) async {
        guard let manager = appState.menuBarManager.hostedVisibilityManager else {
            state = .failed
            return
        }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let apps = manager.bundleIdentifiers(in: section).intersection(running)
        guard !apps.isEmpty else {
            icons = []
            state = .ready
            return
        }
        if icons.isEmpty {
            state = .loading
        }

        let token = await manager.beginTemporaryReveal(apps)
        let captured = await captureWhenDrawn(apps)
        // The shelf shows as soon as the icons are captured.
        Task {
            await manager.endTemporaryReveal(token)
        }

        if let captured {
            icons = captured
            state = .ready
        } else if icons.isEmpty {
            state = .failed
        }
    }

    /// Waits for `apps` to be drawn, then captures their icons, or returns
    /// `nil` if none were drawn.
    private func captureWhenDrawn(_ apps: Set<String>) async -> [Icon]? {
        let start = ContinuousClock.now
        var previous: Set<String>?
        var windows = [AgentWindow]()
        while true {
            windows = Self.readAgentWindows()
            let present = Set(windows.flatMap(\.icons).compactMap(\.bundleIdentifier)).intersection(apps)
            let elapsed = ContinuousClock.now - start
            if
                HostedShelfLayout.isSettled(
                    present: present,
                    previous: previous,
                    expected: apps,
                    elapsed: elapsed,
                    minimumWait: Self.minimumDrawWait
                ) || elapsed >= Self.drawTimeout
            {
                break
            }
            previous = present
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: Self.renderDelay)
        windows = Self.readAgentWindows()

        let captures = Self.captureAgentWindows()
        let candidates = windows.map { window in
            let items = window.icons.map {
                HostedItem(bundleIdentifier: $0.bundleIdentifier, frame: $0.frame, isOwn: $0.isOwn)
            }
            return HostedShelfLayout.entries(items: items, apps: apps)
        }
        // The window with the most icons gives the shelf's icons and order:
        // with a `«`, the item-list window also has the ones behind it.
        guard let entries = candidates.max(by: { $0.count < $1.count }), !entries.isEmpty else {
            Self.logger.debug("The revealed apps weren't drawn: \(apps.sorted().joined(separator: ", "), privacy: .public)")
            return nil
        }

        // Only one window is drawn. With a `«`, it's the one holding it: the
        // item-list window's frames are offset from the drawn icons, and
        // would crop the wrong ones. Otherwise, use the pair of window and
        // capture where the most icons have pixels. Images are matched to
        // the entries by app and index.
        let liveIndex = HostedOverflow.liveWindowIndex(slotIdentifiers: windows.map(\.indicatorIdentifiers))
        let cropSources = liveIndex.map { [candidates[$0]] } ?? candidates
        var best: (images: [HostedShelfEntry.Key: NSImage], drawn: Int)?
        for source in cropSources where !source.isEmpty {
            for capture in captures {
                var images = [HostedShelfEntry.Key: NSImage]()
                for entry in source {
                    images[entry.key] = Self.crop(entry.frame, from: capture)
                }
                if images.count > (best?.drawn ?? -1) {
                    best = (images, images.count)
                }
            }
        }
        let images = best?.images ?? [:]
        let drawn = entries.count { images[$0.key] != nil }
        Self.logger.debug("Captured \(drawn) of \(entries.count) shelf icons")

        return entries.map { entry in
            let image = images[entry.key]
            let app = NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleIdentifier).first
            return Icon(
                entry: entry,
                image: image,
                appIcon: app?.icon,
                displayName: app?.localizedName ?? entry.bundleIdentifier
            )
        }
    }

    // MARK: Pressing

    /// Reveals the icon's app, presses the icon, and hides the app again
    /// once what it opened (a menu, popover or panel) closes.
    ///
    /// Some apps ignore an Accessibility press (OneDrive does). If the app
    /// opens no window after the press, the icon is clicked where the bar
    /// draws it.
    func open(_ entry: HostedShelfEntry, appState: AppState) async {
        guard let manager = appState.menuBarManager.hostedVisibilityManager else {
            return
        }
        let pids = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: entry.bundleIdentifier)
                .map(\.processIdentifier)
        )
        let token = await manager.beginTemporaryReveal([entry.bundleIdentifier])
        let before = Self.windowIDs(of: pids)
        let outcome = await press(entry)

        var opened = Set<CGWindowID>()
        if outcome.isSent {
            opened = await waitForNewWindows(of: pids, before: before, timeout: Self.pressGrace)
        }
        if
            opened.isEmpty,
            let point = outcome.clickPoint,
            !appState.menuBarManager.isMenuBarHiddenBySystem
        {
            Self.logger.debug("\(entry.bundleIdentifier, privacy: .public) opened nothing on a press: clicking it")
            await SystemOverflow.click(at: point, hidEventManager: appState.hidEventManager)
            opened = await waitForNewWindows(of: pids, before: before, timeout: Self.menuGrace)
        }
        if opened.isEmpty {
            Self.logger.debug("\(entry.bundleIdentifier, privacy: .public) icon \(entry.index) opened nothing")
        } else {
            await waitWhileOpen(opened)
        }
        await manager.endTemporaryReveal(token)
    }

    /// What pressing an icon did.
    private struct PressOutcome {
        /// Whether a press was sent to the icon.
        var isSent = false
        /// Where the bar draws the icon, to click it if the press did
        /// nothing, or `nil` if it wasn't found.
        var clickPoint: CGPoint?
    }

    /// Presses the icon once it's drawn. Only waits while the icon isn't
    /// drawn yet: pressing twice would close the menu again. The app's own
    /// element is preferred, and the agent's slot is pressed only if no
    /// element takes presses.
    private func press(_ entry: HostedShelfEntry) async -> PressOutcome {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < Self.drawTimeout {
            let windows = Self.readAgentWindows()
            let found = windows.indices.compactMap { index -> (window: Int, icon: AgentIcon)? in
                let icons = windows[index].icons.map { (bundleIdentifier: $0.bundleIdentifier, frame: $0.frame) }
                return HostedShelfLayout.position(
                    ofIndex: entry.index,
                    bundleIdentifier: entry.bundleIdentifier,
                    in: icons
                ).map { (index, windows[index].icons[$0]) }
            }
            guard !found.isEmpty else {
                try? await Task.sleep(for: .milliseconds(50))
                continue
            }
            // The live window, the one holding the `«`, has the icon's drawn
            // frame. Without a `«`, the windows agree.
            let liveIndex = HostedOverflow.liveWindowIndex(slotIdentifiers: windows.map(\.indicatorIdentifiers))
            let live = found.first { $0.window == liveIndex } ?? found[0]
            var outcome = PressOutcome(clickPoint: CGPoint(x: live.icon.frame.midX, y: live.icon.frame.midY))
            outcome.isSent = found.contains { Self.sendPress(to: $0.icon.element) } || Self.sendPress(to: found[0].icon.slot)
            return outcome
        }
        return PressOutcome()
    }

    /// Presses an element, and returns whether the press was sent: `false`
    /// only if the element doesn't take presses. A press that times out
    /// may still have opened the menu, so it counts as sent.
    private static func sendPress(to element: UIElement) -> Bool {
        element.messagingTimeout = pressTimeout
        do {
            try element.performAction(.press)
            return true
        } catch AXError.actionUnsupported, AXError.invalidUIElement, AXError.attributeUnsupported {
            return false
        } catch {
            logger.debug("Press didn't confirm (\(error, privacy: .public)): counting it as sent")
            return true
        }
    }

    /// The on-screen windows of the given processes.
    private static func windowIDs(of pids: Set<pid_t>) -> Set<CGWindowID> {
        Set(WindowInfo.createWindows(option: .onScreen).filter { pids.contains($0.ownerPID) }.map(\.windowID))
    }

    /// Waits up to `timeout` for the processes to put up windows that
    /// weren't on screen `before`, and returns them.
    private func waitForNewWindows(
        of pids: Set<pid_t>,
        before: Set<CGWindowID>,
        timeout: Duration
    ) async -> Set<CGWindowID> {
        let start = ContinuousClock.now
        while true {
            let opened = Self.windowIDs(of: pids).subtracting(before)
            if !opened.isEmpty || ContinuousClock.now - start >= timeout {
                return opened
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Waits while any of `windows` is still on screen. Popovers can sit at
    /// the normal window level, so any new window counts, not only menus.
    private func waitWhileOpen(_ windows: Set<CGWindowID>) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < Self.menuTimeout {
            let onScreen = Set(WindowInfo.createWindows(option: .onScreen).map(\.windowID))
            guard !onScreen.isDisjoint(with: windows) else {
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    // MARK: Reading the agent

    /// The status items of each of the agent's Accessibility windows.
    private static func readAgentWindows() -> [AgentWindow] {
        guard
            let agent = NSRunningApplication.runningApplications(
                withBundleIdentifier: MenuBarAgentLayout.agentBundleIdentifier
            ).first,
            let app = AXHelpers.application(for: agent)
        else {
            return []
        }
        app.messagingTimeout = MenuBarAgentLayout.messagingTimeout
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return AXHelpers.windows(for: app).map { window in
            var icons = [AgentIcon]()
            var indicatorIdentifiers = [String?]()
            for slot in AXHelpers.children(for: window) {
                guard let frame = AXHelpers.frame(for: slot) else {
                    continue
                }
                // The `«` is the one slot without an element.
                guard let element = AXHelpers.children(for: slot).first else {
                    indicatorIdentifiers.append(AXHelpers.identifier(for: slot))
                    continue
                }
                let pid = AXHelpers.pid(for: element)
                icons.append(AgentIcon(
                    bundleIdentifier: pid.flatMap { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
                    pid: pid,
                    frame: frame,
                    isOwn: pid == ownPID,
                    slot: slot,
                    element: element
                ))
            }
            return AgentWindow(icons: icons, indicatorIdentifiers: indicatorIdentifiers)
        }
    }

    /// A capture of one agent window.
    private struct Capture {
        let image: CGImage
        let bounds: CGRect
    }

    /// Captures every window of the agent.
    private static func captureAgentWindows() -> [Capture] {
        guard
            let agent = NSRunningApplication.runningApplications(
                withBundleIdentifier: MenuBarAgentLayout.agentBundleIdentifier
            ).first
        else {
            return []
        }
        return WindowInfo.createWindows()
            .filter { $0.ownerPID == agent.processIdentifier }
            .compactMap { window in
                ScreenCapture.captureWindow(
                    with: window.windowID,
                    option: [.boundsIgnoreFraming, .bestResolution]
                )
                .map { Capture(image: $0, bounds: window.bounds) }
            }
    }

    /// The icon at `frame` in `capture`, or `nil` if nothing is drawn there.
    private static func crop(_ frame: CGRect, from capture: Capture) -> NSImage? {
        guard capture.bounds.width > 0 else {
            return nil
        }
        let scale = CGFloat(capture.image.width) / capture.bounds.width
        guard
            let rect = HostedShelfLayout.pixelRect(
                of: frame,
                windowBounds: capture.bounds,
                scale: scale,
                imageSize: CGSize(width: capture.image.width, height: capture.image.height)
            ),
            let cropped = capture.image.cropping(to: rect),
            hasVisiblePixels(cropped)
        else {
            return nil
        }
        return NSImage(cgImage: cropped, size: CGSize(width: rect.width / scale, height: rect.height / scale))
    }

    /// Whether enough of the image's pixels aren't transparent for an icon.
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard
                let context = CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else {
            return false
        }
        var visible = 0
        for alpha in stride(from: 3, to: pixels.count, by: 4) where pixels[alpha] > 25 {
            visible += 1
        }
        return visible >= 8
    }
}
