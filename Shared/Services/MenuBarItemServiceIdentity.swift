//
//  MenuBarItemServiceIdentity.swift
//  Shared
//

/// Derives the identifiers of the app and its `MenuBarItemService` helper
/// from each other, so neither is hardcoded.
///
/// The helper's bundle identifier is always the app's bundle identifier
/// plus ``serviceSuffix`` (see `LYNX_BUNDLE_ID` in `Config/Base.xcconfig`).
enum MenuBarItemServiceIdentity {
    /// The suffix that turns the app's bundle identifier into the helper's.
    static let serviceSuffix = ".MenuBarItemService"

    /// Returns the helper's service name for the given app identifier.
    static func serviceName(forHostIdentifier host: String) -> String {
        host + serviceSuffix
    }

    /// Returns the app identifier for the given helper identifier, or `nil`
    /// if the identifier doesn't belong to a helper.
    static func hostIdentifier(forServiceIdentifier service: String) -> String? {
        guard service.hasSuffix(serviceSuffix), service.count > serviceSuffix.count else {
            return nil
        }
        return String(service.dropLast(serviceSuffix.count))
    }
}
