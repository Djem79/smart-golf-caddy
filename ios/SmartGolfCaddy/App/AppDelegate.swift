// ios/SmartGolfCaddy/App/AppDelegate.swift
import FirebaseAppCheck
import FirebaseCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        #if DEBUG
        // Debug provider ДО configure() — иначе SDK попытается App Attest.
        // Токен из консоли Xcode регистрируется в Firebase console → App Check.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #endif
        FirebaseApp.configure()
        ShotQueue.shared.initSync()
        return true
    }
}
