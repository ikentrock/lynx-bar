//
//  HostedAllowlist.swift
//  LynxBar
//

import Cocoa
import ObjectiveC
import OSLog

/// Wraps MenuBarAgent's assessment-mode facility on macOS 27.
///
/// While an assertion is active, MenuBarAgent draws only the menu bar icons
/// of the allowed apps (and of system items). The facility is private
/// (`MenuBarClientCore.framework`), so its classes are looked up at run
/// time, and every piece that is missing makes the facility unavailable
/// instead of crashing.
@available(macOS 27.0, *)
@MainActor
final class HostedAllowlist {
    // `init` methods return a +1 reference (or nil), so their results are
    // typed `Unmanaged` and taken with `takeRetainedValue()`. A plain
    // `AnyObject` result would be treated as +0 and leak every object.
    private typealias InitConfigurationFn = @convention(c) (
        AnyObject, Selector, NSArray, NSArray
    ) -> Unmanaged<AnyObject>?
    private typealias PlainInitFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias ActivateFn = @convention(c) (
        AnyObject, Selector, AnyObject, @convention(block) (NSError?) -> Void
    ) -> Void

    /// Resolves a continuation exactly once, from whichever of the
    /// completion handler and the timeout comes first.
    private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Void, any Error>?

        init(_ continuation: CheckedContinuation<Void, any Error>) {
            self.continuation = continuation
        }

        func finish(_ error: (any Error)?) {
            lock.lock()
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            if let error {
                continuation?.resume(throwing: error)
            } else {
                continuation?.resume()
            }
        }
    }

    enum Failure: LocalizedError {
        case unavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .unavailable: "The allowlist facility isn't available."
            case .timedOut: "The allowlist didn't activate in time."
            }
        }
    }

    private static let logger = Logger(category: "HostedAllowlist")

    private static let frameworkPath =
        "/System/Library/PrivateFrameworks/MenuBarClientCore.framework/MenuBarClientCore"
    private static let initConfigurationSelector =
        NSSelectorFromString("initWithAllowedSystemItems:allowedBundleIdentifiers:")
    private static let activateSelector =
        NSSelectorFromString("activateWithConfiguration:completionHandler:")
    private static let invalidateSelector = NSSelectorFromString("invalidate")
    private static let initSelector = NSSelectorFromString("init")
    private static let allocSelector = NSSelectorFromString("alloc")

    private static let activationTimeout: TimeInterval = 2

    /// The reason found at launch, checked once.
    private static let launchReason: String? = {
        let reason = findLaunchReason()
        if let reason {
            logger.info("Hiding through the allowlist is unavailable: \(reason, privacy: .public)")
        }
        return reason
    }()

    private static func findLaunchReason() -> String? {
        guard HostedSections.isInApplicationsFolder(Bundle.main.bundleURL) else {
            return "Move Lynx Bar to the Applications folder to hide items on macOS 27."
        }
        let unsupported = "This version of macOS doesn't support hiding items."
        guard
            dlopen(frameworkPath, RTLD_NOW) != nil,
            let configurationClass = NSClassFromString("MBAssessmentModeConfiguration"),
            let assertionClass = NSClassFromString("MBAssessmentModeAssertion"),
            class_getInstanceMethod(configurationClass, initConfigurationSelector) != nil,
            class_getInstanceMethod(assertionClass, initSelector) != nil,
            class_getInstanceMethod(assertionClass, activateSelector) != nil,
            class_getInstanceMethod(assertionClass, invalidateSelector) != nil
        else {
            return unsupported
        }
        return nil
    }

    /// The reason found while running, set by `markFailed(_:)`.
    private static var runtimeFailure: String?

    /// Why the facility can't be used, or `nil` if it can.
    ///
    /// Checked once at launch (the framework loads, both classes and all
    /// four selectors exist, and the app is in `/Applications`), and turned
    /// on for the rest of the session by `markFailed(_:)`.
    static var unavailableReason: String? {
        launchReason ?? runtimeFailure
    }

    /// A Boolean value that indicates whether the facility can be used.
    static var isAvailable: Bool {
        unavailableReason == nil
    }

    /// Makes the facility unavailable for the rest of the session.
    static func markFailed(_ reason: String) {
        if runtimeFailure == nil {
            runtimeFailure = reason
        }
    }

    /// The assertion that is active, if any.
    private var current: NSObject?

    /// Bumped by every `apply` and `clear`, so an `apply` that was
    /// suspended can tell that a later call superseded it.
    private var generation = 0

    /// Activates an assertion allowing `bundleIdentifiers` and system items
    /// 0...255, then invalidates the previous one.
    ///
    /// The order matters: the new assertion applies once the old one is
    /// gone, with no flash. If activation fails, the previous assertion is
    /// kept. If another `apply` or `clear` starts while this one is waiting
    /// for activation, this one is superseded: its assertion is invalidated
    /// and it returns without error, leaving the newer call's state alone.
    func apply(allowing bundleIdentifiers: [String]) async throws {
        guard Self.isAvailable else {
            throw Failure.unavailable
        }
        Self.logger.debug("Applying the allowlist with \(bundleIdentifiers.count) apps")
        generation += 1
        let myGeneration = generation
        var new = try Self.makeAssertion(allowing: bundleIdentifiers)
        do {
            try await Self.activate(new.assertion, with: new.configuration)
        } catch Failure.timedOut where generation == myGeneration {
            // A slow activation at login or wake shouldn't turn hiding off
            // for the session: try once more with a fresh assertion.
            Self.logger.info("Allowlist activation timed out: retrying once")
            Self.invalidate(new.assertion)
            new = try Self.makeAssertion(allowing: bundleIdentifiers)
            do {
                try await Self.activate(new.assertion, with: new.configuration)
            } catch {
                Self.logger.error("Allowlist activation failed again: \(error, privacy: .public)")
                Self.invalidate(new.assertion)
                throw error
            }
        } catch {
            Self.logger.error("Allowlist activation failed: \(error, privacy: .public)")
            Self.invalidate(new.assertion)
            throw error
        }
        guard generation == myGeneration else {
            Self.logger.debug("Allowlist apply superseded")
            Self.invalidate(new.assertion)
            return
        }
        let old = current
        current = new.assertion
        if let old {
            Self.invalidate(old)
        }
    }

    /// Invalidates the active assertion, if any. Everything is drawn again.
    func clear() {
        Self.logger.debug("Clearing the allowlist (active: \(self.current != nil))")
        generation += 1
        if let current {
            Self.invalidate(current)
        }
        current = nil
    }

    private static func makeAssertion(
        allowing bundleIdentifiers: [String]
    ) throws -> (assertion: NSObject, configuration: AnyObject) {
        guard
            let configurationClass = NSClassFromString("MBAssessmentModeConfiguration") as? NSObject.Type,
            let assertionClass = NSClassFromString("MBAssessmentModeAssertion") as? NSObject.Type,
            let initConfigurationImp = class_getMethodImplementation(
                configurationClass,
                initConfigurationSelector
            ),
            let initImp = class_getMethodImplementation(assertionClass, initSelector),
            let rawConfiguration = configurationClass.perform(allocSelector)
        else {
            throw Failure.unavailable
        }
        // `init` consumes the `alloc` result, so that one is passed unretained.
        guard
            let configuration = unsafeBitCast(initConfigurationImp, to: InitConfigurationFn.self)(
                rawConfiguration.takeUnretainedValue(),
                initConfigurationSelector,
                NSArray(array: (0...255).map { NSNumber(value: $0) }),
                NSArray(array: bundleIdentifiers)
            )?.takeRetainedValue(),
            let rawAssertion = assertionClass.perform(allocSelector),
            let assertion = unsafeBitCast(initImp, to: PlainInitFn.self)(
                rawAssertion.takeUnretainedValue(),
                initSelector
            )?.takeRetainedValue() as? NSObject
        else {
            throw Failure.unavailable
        }
        return (assertion, configuration)
    }

    /// Activates `assertion`, failing if the completion handler reports an
    /// error or doesn't run within the timeout.
    private static func activate(_ assertion: NSObject, with configuration: AnyObject) async throws {
        guard
            let imp = class_getMethodImplementation(type(of: assertion), activateSelector)
        else {
            throw Failure.unavailable
        }
        let activate = unsafeBitCast(imp, to: ActivateFn.self)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let oneShot = OneShot(continuation)
            // Stored in a constant so the block can escape.
            let completion: @convention(block) (NSError?) -> Void = { error in
                oneShot.finish(error)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + activationTimeout) {
                oneShot.finish(Failure.timedOut)
            }
            activate(assertion, activateSelector, configuration, completion)
        }
    }

    private static func invalidate(_ assertion: NSObject) {
        _ = assertion.perform(invalidateSelector)
    }
}
