//
//  IceSettingsImporter.swift
//  Ice
//

import Foundation
import OSLog

/// Copies Ice's settings into Lynx Bar's defaults on first launch.
///
/// Lynx Bar has its own bundle identifier, so it starts with an empty
/// defaults domain. This runs before any settings are read, and before
/// `MigrationManager`, so imported settings in older formats still get
/// migrated. Ice's own domain is only read.
enum IceSettingsImporter {
    /// The defaults domain of Ice.
    static let sourceDomain = "com.jordanbaird.Ice"

    /// The key that records that the import has run.
    static let importedFlagKey = "hasImportedIceSettings"

    /// The result of an import attempt.
    enum Outcome: Equatable {
        /// The import already ran on an earlier launch.
        case alreadyImported
        /// Ice has no settings to import.
        case noSourceSettings
        /// The given number of keys were copied.
        case imported(keyCount: Int)
    }

    private static let logger = Logger(category: "IceSettingsImporter")

    /// Copies keys from `source` that `defaults` doesn't have yet, once.
    ///
    /// The flag is set even if there is nothing to import, so the import
    /// happens on the first launch or never.
    @discardableResult
    static func importIfNeeded(source: [String: Any]?, into defaults: UserDefaults) -> Outcome {
        guard !defaults.bool(forKey: importedFlagKey) else {
            return .alreadyImported
        }
        defer {
            defaults.set(true, forKey: importedFlagKey)
        }
        guard let source, !source.isEmpty else {
            return .noSourceSettings
        }
        var count = 0
        for (key, value) in source where key != importedFlagKey && defaults.object(forKey: key) == nil {
            defaults.set(value, forKey: key)
            count += 1
        }
        return .imported(keyCount: count)
    }

    /// Imports Ice's settings into the standard defaults, once.
    @discardableResult
    static func importIfNeeded() -> Outcome {
        let outcome = importIfNeeded(
            source: UserDefaults.standard.persistentDomain(forName: sourceDomain),
            into: .standard
        )
        logger.info("Ice settings import: \(String(describing: outcome), privacy: .public)")
        return outcome
    }
}
