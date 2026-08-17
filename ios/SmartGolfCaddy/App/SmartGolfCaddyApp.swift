// ios/SmartGolfCaddy/App/SmartGolfCaddyApp.swift
import SwiftUI

@main
struct SmartGolfCaddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { RootView() }
    }
}
