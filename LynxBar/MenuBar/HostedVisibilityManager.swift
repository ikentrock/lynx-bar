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

    /// The state of the last allowlist applied or cleared.
    private var applied = AppliedState(hidesHidden: false, hidesAlwaysHidden: false)

    /// The last queued job. Every new job waits for it.
    private var tail: Task<Void, Never>?

    /// Bumped by `clear()`, so jobs queued before it don't run.
    private var generation = 0

    /// Set when applying failed. Nothing runs after that.
    private var isStopped = false

    private var observers = [NSObjectProtocol]()

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

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.didLaunchApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reapply()
                }
            })
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

    /// Re-applies the current allowlist (after wake).
    func reapply() {
        enqueue()
    }

    /// Lifts the restriction, so every icon is drawn, and drops queued work.
    func clear() {
        generation += 1
        tail = nil
        applied = AppliedState(hidesHidden: false, hidesAlwaysHidden: false)
        allowlist.clear()
    }

    private func enqueue() {
        guard !isStopped else {
            return
        }
        let previous = tail
        let myGeneration = generation
        tail = Task { [weak self] in
            await previous?.value
            guard let self, !isStopped, generation == myGeneration else {
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
            (state.hidesHidden && !applied.hidesHidden) ||
            (state.hidesAlwaysHidden && !applied.hidesAlwaysHidden)
        {
            // Everything is drawn right before a section hides.
            readSets(from: MenuBarAgentLayout.current())
        }

        var excluded = Set<String>()
        if state.hidesHidden {
            excluded.formUnion(sets.hidden)
        }
        if state.hidesAlwaysHidden {
            excluded.formUnion(sets.alwaysHidden)
        }
        guard !excluded.isEmpty else {
            if applied.hidesAny {
                Self.logger.debug("Nothing to hide: clearing the allowlist")
                allowlist.clear()
            }
            applied = state
            return
        }

        let layout = MenuBarAgentLayout.current()
        var candidates = Set(layout?.listItems.compactMap(\.bundleIdentifier) ?? [])
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy != .prohibited {
            if let id = app.bundleIdentifier {
                candidates.insert(id)
            }
        }
        let allowed = HostedSections.allowlist(
            sets: sets,
            hidesHidden: state.hidesHidden,
            hidesAlwaysHidden: state.hidesAlwaysHidden,
            candidates: candidates,
            ownBundleIdentifier: ownBundleIdentifier
        )
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
            needsFirstRead = !readSets(from: MenuBarAgentLayout.current())
            return
        }
        hasWaitedForFirstRead = true
        let deadline = ContinuousClock.now + Self.firstReadTimeout
        while true {
            let isLastTry = ContinuousClock.now >= deadline
            if readSets(from: MenuBarAgentLayout.current(), logsFailure: isLastTry) {
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

    /// The dividers' frames in the item list, `nil` for a disabled section,
    /// or `nil` overall if they can't be found.
    ///
    /// They're matched by order, not by their windows' frames: our status
    /// item windows can follow the agent's other window, where a divider has
    /// another width. Our items sit always-hidden divider, hidden divider,
    /// Lynx icon, left to right, so the list must hold exactly one item of
    /// ours per section in the bar.
    private func dividerFrames(in layout: MenuBarAgentLayout) -> (hidden: CGRect?, alwaysHidden: CGRect?)? {
        guard let menuBarManager = appState?.menuBarManager else {
            return nil
        }
        let names = [MenuBarSection.Name.alwaysHidden, .hidden, .visible].filter {
            menuBarManager.controlItem(withName: $0)?.isAddedToMenuBar ?? false
        }
        let ownFrames = layout.listItems.filter(\.isOwn).map(\.frame)
        guard !ownFrames.isEmpty, ownFrames.count == names.count else {
            return nil
        }
        let frames = Dictionary(uniqueKeysWithValues: zip(names, ownFrames))
        return (frames[.hidden], frames[.alwaysHidden])
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
