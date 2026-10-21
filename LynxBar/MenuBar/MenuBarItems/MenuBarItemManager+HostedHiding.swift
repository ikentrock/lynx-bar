//
//  MenuBarItemManager+HostedHiding.swift
//  LynxBar
//

import Cocoa

// MARK: - Hosted Hiding (macOS 27)

extension MenuBarItemManager {
    /// Requests a hiding-width measurement after the given delay. Does
    /// nothing before macOS 27.
    func requestHostedMeasurement(after delay: Duration = .zero) {
        guard #available(macOS 27.0, *) else {
            return
        }
        Task { @MainActor [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            self?.hostedMeasurementRequests.send()
        }
    }

    /// Measures how wide each section divider should be to hide its section,
    /// and recovers dividers the system dropped from the bar.
    ///
    /// Ported from IceMelt (https://github.com/pnikolaidis/icemelt, PR #46),
    /// GPL-3.0. See ``HostedHidingWidth`` for the rules.
    @available(macOS 27.0, *)
    func updateHostedHidingWidths() {
        guard
            let menuBarManager = appState?.menuBarManager,
            let layout = MenuBarAgentLayout.current(),
            let screen = NSScreen.screenWithActiveMenuBar ?? NSScreen.main
        else {
            return
        }

        // While the system's overflow is open, the divider is squeezed to a
        // point and its slot no longer matches its window, which would look
        // like a dropped divider. Measure again once it closes.
        guard !layout.isOverflowExpanded else {
            return
        }

        let regionLeft = hostedRegionLeft(on: screen)
        var widths = hostedHidingWidths
        var toReset = hostedDividersToReset

        let hiddenIsHiding = menuBarManager.section(withName: .hidden)?.controlItem.state == .hideSection

        for identifier in [ControlItem.Identifier.hidden, .alwaysHidden] {
            guard
                let section = menuBarManager.section(withName: identifier == .hidden ? .hidden : .alwaysHidden),
                section.isEnabled,
                let windowFrame = section.controlItem.frame
            else {
                continue
            }

            let slot = HostedHidingWidth.slot(forWindowFrame: windowFrame, in: layout.ownSlots)
            var state = hostedDividerStates[identifier, default: HostedHidingWidth.DividerState()]
            let action = state.update(
                hasSlot: slot != nil,
                isHiding: section.controlItem.state == .hideSection,
                // The always-hidden divider sits inside the hidden region
                // while the hidden section is hidden.
                isCovered: identifier == .alwaysHidden && hiddenIsHiding
            )
            hostedDividerStates[identifier] = state
            if state.isResetting {
                toReset.insert(identifier)
            } else {
                toReset.remove(identifier)
            }

            switch action {
            case .ignore:
                continue
            case .reset:
                logger.info("Divider \(identifier.rawValue, privacy: .public) isn't in the menu bar; resetting it")
                requestHostedMeasurement(after: .milliseconds(600))
                continue
            case .giveUp:
                logger.error("Divider \(identifier.rawValue, privacy: .public) keeps dropping out of the menu bar; giving up until the section is shown")
                continue
            case .measureAndVerify:
                requestHostedMeasurement(after: .milliseconds(600))
            case .measure:
                break
            }

            guard let slot else {
                continue
            }
            // The divider grows leftwards, so its right edge is where the
            // items that stay visible begin.
            let width = HostedHidingWidth.width(visibleFrom: slot.maxX, regionLeft: regionLeft)
            if HostedHidingWidth.shouldApply(old: widths[identifier], new: width) {
                widths[identifier] = width
            }
        }

        setHostedHidingWidths(widths)
        setHostedDividersToReset(toReset)
    }

    /// Returns where the agent's item area begins on the given screen.
    @available(macOS 27.0, *)
    private func hostedRegionLeft(on screen: NSScreen) -> CGFloat {
        guard let applicationMenuFrame = screen.getApplicationMenuFrame() else {
            // A cautious guess that may hide fewer items.
            return HostedHidingWidth.regionLeft(applicationMenuMaxX: screen.frame.midX, notchMaxX: nil)
        }
        // The application menu is reported on the main display, but it's
        // the same width on every display.
        let displayBounds = CGDisplayBounds(screen.displayID)
        let mainDisplayBounds = CGDisplayBounds(CGMainDisplayID())
        let applicationMenuMaxX = displayBounds.minX + (applicationMenuFrame.maxX - mainDisplayBounds.minX)
        return HostedHidingWidth.regionLeft(
            applicationMenuMaxX: applicationMenuMaxX,
            notchMaxX: screen.frameOfNotch?.maxX
        )
    }
}
