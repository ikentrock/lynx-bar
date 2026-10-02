//
//  main.swift
//  Tests
//

import Foundation

/// Creates a scratch defaults domain and removes it afterwards.
func withScratchDefaults(_ body: (UserDefaults) -> Void) {
    let name = "com.ikentrock.LynxBar.tests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: name) else {
        expect(false, "couldn't create scratch defaults \(name)")
        return
    }
    body(defaults)
    defaults.removePersistentDomain(forName: name)
}

// Imports everything on first run and sets the flag.
withScratchDefaults { defaults in
    let source: [String: Any] = ["UseIceBar": true, "IceBarLocation": 2, "Ice.ControlItem.Hidden": 481]
    let outcome = IceSettingsImporter.importIfNeeded(source: source, into: defaults)
    expect(outcome == .imported(keyCount: 3), "imports all keys (got \(outcome))")
    expect(defaults.bool(forKey: "UseIceBar"), "copies a Bool")
    expect(defaults.integer(forKey: "IceBarLocation") == 2, "copies an Int")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "sets the flag")
}

// Never overwrites values Lynx Bar already has.
withScratchDefaults { defaults in
    defaults.set(5, forKey: "IceBarLocation")
    let outcome = IceSettingsImporter.importIfNeeded(source: ["IceBarLocation": 2, "UseIceBar": true], into: defaults)
    expect(outcome == .imported(keyCount: 1), "imports only missing keys (got \(outcome))")
    expect(defaults.integer(forKey: "IceBarLocation") == 5, "keeps the existing value")
}

// Runs only once.
withScratchDefaults { defaults in
    IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults)
    defaults.set(false, forKey: "UseIceBar")
    let outcome = IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults)
    expect(outcome == .alreadyImported, "second run is a no-op (got \(outcome))")
    expect(!defaults.bool(forKey: "UseIceBar"), "second run doesn't copy again")
}

// Missing or empty source: nothing copied, but the flag is set (first launch or never).
withScratchDefaults { defaults in
    expect(IceSettingsImporter.importIfNeeded(source: nil, into: defaults) == .noSourceSettings, "nil source")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "flag set without source")
    expect(
        IceSettingsImporter.importIfNeeded(source: ["UseIceBar": true], into: defaults) == .alreadyImported,
        "a later Ice install isn't imported"
    )
}
withScratchDefaults { defaults in
    expect(IceSettingsImporter.importIfNeeded(source: [:], into: defaults) == .noSourceSettings, "empty source")
}

// The source's own flag key is never copied.
withScratchDefaults { defaults in
    let source: [String: Any] = [IceSettingsImporter.importedFlagKey: false, "A": 1]
    let outcome = IceSettingsImporter.importIfNeeded(source: source, into: defaults)
    expect(outcome == .imported(keyCount: 1), "skips the flag key (got \(outcome))")
    expect(defaults.bool(forKey: IceSettingsImporter.importedFlagKey), "flag ends up true")
}

finishTests("IceSettingsImporter")
