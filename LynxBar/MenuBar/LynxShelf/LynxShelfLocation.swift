//
//  LynxShelfLocation.swift
//  LynxBar
//

import SwiftUI

/// Locations where the Lynx Shelf can appear.
enum LynxShelfLocation: Int, CaseIterable, Identifiable {
    /// The Lynx Shelf will appear in different locations based on context.
    case dynamic = 0

    /// The Lynx Shelf will appear centered below the mouse pointer.
    case mousePointer = 1

    /// The Lynx Shelf will appear centered below the Lynx icon.
    case lynxIcon = 2

    var id: Int { rawValue }

    /// Localized string key representation.
    var localized: LocalizedStringKey {
        switch self {
        case .dynamic: "Dynamic"
        case .mousePointer: "Mouse pointer"
        case .lynxIcon: "Lynx icon"
        }
    }
}
