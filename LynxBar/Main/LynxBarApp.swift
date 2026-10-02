//
//  LynxBarApp.swift
//  LynxBar
//

import SwiftUI

@main
struct LynxBarApp: App {
    @NSApplicationDelegateAdaptor var appDelegate: AppDelegate

    var body: some Scene {
        SettingsWindow(appState: appDelegate.appState)
        PermissionsWindow(appState: appDelegate.appState)
    }
}
