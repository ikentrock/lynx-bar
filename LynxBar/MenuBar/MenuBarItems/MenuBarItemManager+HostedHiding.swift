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

        let regionLeft = hostedRegionLeft(on: screen)
        var widths = hostedHidingWidths
        var toReset = hostedDividersToReset

        for identifier in [ControlItem.Identifier.hidden, .alwaysHidden] {
            guard
                let section = menuBarManager.section(withName: identifier == .hidden ? .hidden : .alwaysHidden),
                section.isEnabled,
                let windowFrame = section.controlItem.frame
            else {
                continue
            }

            let slot = HostedHidingWidth.slot(forWindowFrame: windowFrame, in: layout.ownSlots)

            if slot == nil, section.controlItem.state == .hideSection {
                // Dropped by the system (too wide, or stretched before it had
                // a place). Take the standard length so it returns, then
                // measure again. Counts every miss, including one right after
                // a reset, so a divider that never returns can't loop.
                let count = hostedResetCounts[identifier, default: 0]
                guard HostedHidingWidth.shouldReset(resetCount: count) else {
                    if count == HostedHidingWidth.maxResets {
                        logger.error("Divider \(identifier.rawValue, privacy: .public) keeps dropping out of the menu bar; giving up")
                        hostedResetCounts[identifier] = count + 1 // Log once.
                    }
                    continue
                }
                logger.info("Divider \(identifier.rawValue, privacy: .public) isn't in the menu bar; resetting it")
                hostedResetCounts[identifier] = count + 1
                toReset.insert(identifier)
                requestHostedMeasurement(after: .milliseconds(600))
                continue
            }

            if slot != nil, section.controlItem.state == .hideSection {
                if toReset.remove(identifier) == nil {
                    // In the bar at its hiding length, so any loop is over.
                    hostedResetCounts[identifier] = 0
                }
            }

            guard let visibleFrom = HostedHidingWidth.visibleFrom(
                dividerSlot: slot,
                otherSlots: layout.otherSlots,
                chevron: layout.chevron
            ) else {
                continue
            }
            let width = HostedHidingWidth.width(visibleFrom: visibleFrom, regionLeft: regionLeft)
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
