//
//  HostedVisibilityManager.swift
//  LynxBar
//

import Cocoa
import OSLog

/// Hides and shows the sections on macOS 27 through MenuBarAgent's
/// allowlist.
///
/// The apps in each section are kept in two sets, stored in `UserDefaults`.
/// Hiding a section activates an allowlist that leaves its apps out, and
/// showing it lifts the restriction again.
@available(macOS 27.0, *)
@MainActor
final class HostedVisibilityManager {
    /// The sections' hiding states that an allowlist was applied for.
    private struct AppliedState: Equatable {
        var hidesHidden: Bool
        var hidesAlwaysHidden: Bool

        var hidesAny: Bool { hidesHidden || hidesAlwaysHidden }
    }

    private static let logger = Logger(category: "HostedVisibility")

    /// How long to wait at launch for the dividers to show up in the agent's
    /// item list before computing the sets.
    private static let firstReadTimeout: Duration = .seconds(3)

    private weak var appState: AppState?

    private let allowlist = HostedAllowlist()

    private var sets: HostedSectionSets

    /// Whether the sets still have to be read from the bar for the first time.
    private var needsFirstRead: Bool

    /// Whether the first read already waited for the dividers once.
    private var hasWaitedForFirstRead = false

    /// The state of the last allowlist applied or cleared, `nil` until the
    /// first one. The launch apply doesn't re-read the bar: the stored sets
    /// are kept as they are.
    private var applied: AppliedState?

    /// The last queued job. Every new job waits for it.
    private var tail: Task<Void, Never>?

    /// Bumped by `clear()`, so jobs queued before it don't run.
    private var generation = 0

    /// How many queued jobs haven't started yet. A reapply is dropped
    /// while one is waiting, since that job reads the current state anyway.
    private var waitingJobs = 0

    /// The bundle identifiers the active allowlist was built from, allowed
    /// or excluded, or `nil` while nothing is hidden. Set when an apply
    /// starts, so an app that launches during it still counts as new.
    private var coveredBundleIdentifiers: Set<String>?

    /// Set when applying failed. Nothing runs after that.
    private var isStopped = false

    private var observers = [NSObjectProtocol]()

    /// Observes the running apps, so apps that launch while a section is
    /// hidden are allowed, background and LSUIElement ones included, which
    /// `didLaunchApplicationNotification` doesn't report.
    private var runningAppsObservation: NSKeyValueObservation?

    /// The running apps that have a bundle identifier, by process
    /// identifier, as last seen. Compared by process, so an app (such as
    /// MenuBarAgent) that quits and relaunches between two looks still
    /// counts as added.
    private var runningApps: [pid_t: String]

    /// Whether a reapply for new running apps is already scheduled for the
    /// next run-loop turn.
    private var isRunningAppsReapplyScheduled = false

    /// The bundle identifiers of the last non-empty read of the agent's
    /// item list. Under an assertion, an app whose AX read fails would
    /// otherwise drop out of the allowlist.
    private var lastListedBundleIdentifiers = Set<String>()

    private var ownBundleIdentifier: String { Constants.bundleIdentifier }

    init(appState: AppState) {
        self.appState = appState
        let hidden = Defaults.stringArray(forKey: .hostedHiddenApps)
        let alwaysHidden = Defaults.stringArray(forKey: .hostedAlwaysHiddenApps)
        self.sets = HostedSectionSets(
            hidden: Set(hidden ?? []),
            alwaysHidden: Set(alwaysHidden ?? [])
        )
        self.needsFirstRead = hidden == nil && alwaysHidden == nil
        if !needsFirstRead {
            Self.logger.debug("Loaded the hidden apps: \(Self.describe(self.sets), privacy: .public)")
        }

        self.runningApps = Self.bundleIdentifiersByPID(of: NSWorkspace.shared.runningApplications)

        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reapply()
                }
            }
        )
        // Not necessarily called on the main thread.
        runningAppsObservation = NSWorkspace.shared.observe(\.runningApplications, options: [.new, .old]) { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.runningAppsDidChange()
                }
            }
        }

        // Sections start hidden, so apply their current states right away.
        sectionsDidChange()
    }

    /// Reads the bar (when a section is about to hide), updates and stores
    /// the sets, and applies the allowlist for the sections' current states.
    /// Calls are serialized: each waits for the one before it.
    func sectionsDidChange() {
        enqueue()
    }

    /// Re-applies the current allowlist (after wake, or when apps launch).
    /// Does nothing while another job is waiting to run.
    func reapply() {
        guard waitingJobs == 0 else {
            return
        }
        enqueue()
    }

    /// The bundle identifiers of the hidden apps that are being shown now:
    /// the set of each enabled section that isn't hidden. Rehiding waits
    /// while one of these apps has a menu, popover or panel open.
    var revealedBundleIdentifiers: Set<String> {
        guard let menuBarManager = appState?.menuBarManager else {
            return []
        }
        var revealed = Set<String>()
        if let section = menuBarManager.section(withName: .hidden), section.isEnabled, !section.isHidden {
            revealed.formUnion(sets.hidden)
        }
        if let section = menuBarManager.section(withName: .alwaysHidden), section.isEnabled, !section.isHidden {
            revealed.formUnion(sets.alwaysHidden)
        }
        return revealed
    }

    /// Lifts the restriction, so every icon is drawn, and drops queued work.
    func clear() {
        generation += 1
        tail = nil
        waitingJobs = 0
        coveredBundleIdentifiers = nil
        applied = AppliedState(hidesHidden: false, hidesAlwaysHidden: false)
        allowlist.clear()
    }

    /// Reapplies, at most once per run-loop turn, when apps the active
    /// allowlist doesn't account for were added to the running apps, or
    /// MenuBarAgent relaunched, which drops the assertion. Helper processes
    /// of apps already allowed don't reapply.
    private func runningAppsDidChange() {
        let current = Self.bundleIdentifiersByPID(of: NSWorkspace.shared.runningApplications)
        let added = Set(current.compactMap { pid, id in runningApps[pid] == nil ? id : nil })
        runningApps = current
        guard
            !isStopped,
            !isRunningAppsReapplyScheduled,
            HostedSections.needsReapply(
                added: added,
                covered: coveredBundleIdentifiers,
                agentBundleIdentifier: MenuBarAgentLayout.agentBundleIdentifier
            )
        else {
            return
        }
        isRunningAppsReapplyScheduled = true
        let isAgent = added.contains(MenuBarAgentLayout.agentBundleIdentifier)
        Self.logger.debug(
            "Running apps added \(added.sorted().joined(separator: ", "), privacy: .public): reapplying"
        )
        Task { [weak self] in
            // A relaunched agent needs a moment before it takes assertions.
            if isAgent {
                try? await Task.sleep(for: .seconds(1))
            }
            guard let self else {
                return
            }
            isRunningAppsReapplyScheduled = false
            reapply()
        }
    }

    private static func bundleIdentifiers(of apps: [NSRunningApplication]) -> Set<String> {
        Set(apps.compactMap(\.bundleIdentifier))
    }

    private static func bundleIdentifiersByPID(of apps: [NSRunningApplication]) -> [pid_t: String] {
        var result = [pid_t: String]()
        for app in apps {
            if let id = app.bundleIdentifier {
                result[app.processIdentifier] = id
            }
        }
        return result
    }

    private func enqueue() {
        guard !isStopped else {
            return
        }
        let previous = tail
        let myGeneration = generation
        waitingJobs += 1
        tail = Task { [weak self] in
            await previous?.value
            guard let self, generation == myGeneration else {
                return
            }
            waitingJobs -= 1
            guard !isStopped else {
                return
            }
            await update(generation: myGeneration)
        }
    }

    /// Applies the allowlist for the sections' states as they are now.
    private func update(generation myGeneration: Int) async {
        guard let menuBarManager = appState?.menuBarManager else {
            return
        }
        let hiddenSection = menuBarManager.section(withName: .hidden)
        let alwaysHiddenSection = menuBarManager.section(withName: .alwaysHidden)
        let state = AppliedState(
            hidesHidden: hiddenSection.map { $0.isEnabled && $0.isHidden } ?? false,
            hidesAlwaysHidden: alwaysHiddenSection.map { $0.isEnabled && $0.isHidden } ?? false
        )

        if needsFirstRead {
            await readFirstSets()
        } else if
            let applied,
            (state.hidesHidden && !applied.hidesHidden) ||
            (state.hidesAlwaysHidden && !applied.hidesAlwaysHidden)
        {
            // Everything is drawn right before a section hides.
            readSets(from: currentLayout())
        }

        var excluded = Set<String>()
        if state.hidesHidden {
            excluded.formUnion(sets.hidden)
        }
        if state.hidesAlwaysHidden {
            excluded.formUnion(sets.alwaysHidden)
        }
        guard !excluded.isEmpty else {
            if applied?.hidesAny ?? false {
                Self.logger.debug("Nothing to hide: clearing the allowlist")
                allowlist.clear()
            }
            coveredBundleIdentifiers = nil
            applied = state
            return
        }

        let layout = currentLayout()
        if let layout {
            // Only logs how our items match in the list, for diagnosis.
            _ = dividerFrames(in: layout)
        }
        // Allowing extra apps is harmless, so every running app is allowed,
        // background ones included: some own status items.
        let listed = Set(layout?.listItems.compactMap(\.bundleIdentifier) ?? [])
        if !listed.isEmpty {
            lastListedBundleIdentifiers = listed
        }
        var candidates = lastListedBundleIdentifiers
        candidates.formUnion(Self.bundleIdentifiers(of: NSWorkspace.shared.runningApplications))
        let allowed = HostedSections.allowlist(
            sets: sets,
            hidesHidden: state.hidesHidden,
            hidesAlwaysHidden: state.hidesAlwaysHidden,
            candidates: candidates,
            ownBundleIdentifier: ownBundleIdentifier
        )
        coveredBundleIdentifiers = candidates.union(excluded)
        Self.logger.debug(
            """
            Applying the allowlist: \(allowed.count) apps allowed, \
            \(excluded.count) excluded (\(excluded.sorted().joined(separator: ", "), privacy: .public))
            """
        )

        do {
            try await allowlist.apply(allowing: allowed)
            // A `clear()` while activating already reset the state.
            if generation == myGeneration {
                applied = state
            }
        } catch {
            fail(error)
        }
    }

    /// Computes the sets for the first time, once the dividers can be found
    /// in the agent's item list. Nothing is stored if they can't. Only the
    /// first try waits for them.
    private func readFirstSets() async {
        guard !hasWaitedForFirstRead else {
            needsFirstRead = !readSets(from: currentLayout())
            return
        }
        hasWaitedForFirstRead = true
        let deadline = ContinuousClock.now + Self.firstReadTimeout
        while true {
            let isLastTry = ContinuousClock.now >= deadline
            if readSets(from: currentLayout(), logsFailure: isLastTry) {
                needsFirstRead = false
                return
            }
            guard !isLastTry else {
                Self.logger.debug("Couldn't read the bar yet: the hidden apps stay unset")
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Updates and stores the sets from where the icons sit in `layout`.
    /// Returns `false`, keeping the sets, if the dividers can't be found.
    @discardableResult
    private func readSets(from layout: MenuBarAgentLayout?, logsFailure: Bool = true) -> Bool {
        guard
            let layout,
            let dividers = dividerFrames(in: layout)
        else {
            if logsFailure {
                let own = layout?.listItems.filter(\.isOwn).map { "\($0.frame)" } ?? []
                Self.logger.debug(
                    """
                    Couldn't find the dividers in the bar: keeping the hidden apps \
                    (own list items \(own, privacy: .public))
                    """
                )
            }
            return false
        }
        let listed = Set(layout.listItems.compactMap(\.bundleIdentifier))
        if !listed.isEmpty {
            lastListedBundleIdentifiers = listed
        }
        sets = HostedSections.updatedSets(
            sets,
            items: layout.listItems,
            hiddenDivider: dividers.hidden,
            alwaysHiddenDivider: dividers.alwaysHidden,
            ownBundleIdentifier: ownBundleIdentifier
        )
        Defaults.set(sets.hidden.sorted(), forKey: .hostedHiddenApps)
        Defaults.set(sets.alwaysHidden.sorted(), forKey: .hostedAlwaysHiddenApps)
        Self.logger.debug("Read the hidden apps from the bar: \(Self.describe(self.sets), privacy: .public)")
        return true
    }

    /// The sections whose control items are in the bar, in the order their
    /// items sit left to right when the owner hasn't moved them.
    private func sectionsInBar() -> [MenuBarSection] {
        guard let menuBarManager = appState?.menuBarManager else {
            return []
        }
        return [MenuBarSection.Name.alwaysHidden, .hidden, .visible].compactMap { name in
            menuBarManager.section(withName: name).flatMap { $0.controlItem.isAddedToMenuBar ? $0 : nil }
        }
    }

    /// Reads the agent's layout, choosing its item-list window by our own
    /// status item windows.
    private func currentLayout() -> MenuBarAgentLayout? {
        MenuBarAgentLayout.current(ownWindowFrames: sectionsInBar().compactMap(\.controlItem.frame))
    }

    /// The dividers' frames in the item list, `nil` for a disabled section,
    /// or `nil` overall if they can't be found.
    ///
    /// Each of our windows is matched to its own item in the list by
    /// ``HostedHidingWidth/slot(forWindowFrame:in:)``. If some don't match,
    /// our items are matched by their usual order instead (always-hidden
    /// divider, hidden divider, Lynx icon), but only if that order agrees
    /// with every item that did match. The owner may have moved them.
    private func dividerFrames(in layout: MenuBarAgentLayout) -> (hidden: CGRect?, alwaysHidden: CGRect?)? {
        let sections = sectionsInBar()
        let ownFrames = layout.listItems.filter(\.isOwn).map(\.frame)
        guard !sections.isEmpty, !ownFrames.isEmpty else {
            return nil
        }
        let matched = sections.map { section in
            section.controlItem.frame.flatMap { HostedHidingWidth.slot(forWindowFrame: $0, in: ownFrames) }
        }
        guard let result = HostedSections.ownItemSlots(matched: matched, ownSlots: ownFrames) else {
            return nil
        }
        logMatch(result.match == .byFrame ? "by frame" : "by order", layout: layout)
        let frames = Dictionary(uniqueKeysWithValues: zip(sections.map(\.name), result.slots))
        return (frames[.hidden], frames[.alwaysHidden])
    }

    private func logMatch(_ how: String, layout: MenuBarAgentLayout) {
        let window = layout.listWindowChoice.map { "window \($0.index) (\($0.reason))" } ?? "no window"
        Self.logger.debug("Matched our items \(how, privacy: .public) in the list, \(window, privacy: .public)")
    }

    /// Stops using the allowlist for the rest of the session.
    private func fail(_ error: any Error) {
        Self.logger.error("Hiding through the allowlist failed: \(error, privacy: .public)")
        isStopped = true
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        runningAppsObservation = nil
        HostedAllowlist.markFailed(error.localizedDescription)
        clear()
        appState?.menuBarManager.removeHostedVisibility()
    }

    private static func describe(_ sets: HostedSectionSets) -> String {
        let hidden = sets.hidden.sorted().joined(separator: ", ")
        let alwaysHidden = sets.alwaysHidden.sorted().joined(separator: ", ")
        return "hidden [\(hidden)], always-hidden [\(alwaysHidden)]"
    }
}
