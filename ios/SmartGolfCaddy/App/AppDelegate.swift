// ios/SmartGolfCaddy/App/AppDelegate.swift
import FirebaseAppCheck
import FirebaseCore
import UIKit

// Release/TestFlight/App Store: App Attest. Все callable на сервере стоят
// с enforceAppCheck, поэтому без провайдера релизная сборка не смогла бы
// записать ни одного удара. Требует: entitlement
// com.apple.developer.devicecheck.appattest-environment = production
// (App Check не принимает токены sandbox-окружения) и регистрацию
// iOS-приложения с провайдером App Attest в Firebase console →
// App Check (SETUP.md, раздел App Check).
final class AppAttestProviderFactory: NSObject, AppCheckProviderFactory {
    func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        AppAttestProvider(app: app)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Провайдер App Check — строго ДО configure().
        #if DEBUG
        // Debug provider: токен из консоли Xcode регистрируется в Firebase
        // console → App Check (см. SETUP.md, шаг 5 раздела iOS).
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
        ShotQueue.shared.initSync()
        WatchBridge.shared.activate()
        return true
    }
}
