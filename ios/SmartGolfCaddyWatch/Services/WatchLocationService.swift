// ios/SmartGolfCaddyWatch/Services/WatchLocationService.swift
// Обёртка CLLocationManager на watchOS (when-in-use). ЕДИНСТВЕННЫЙ файл
// watch-таргета, которому разрешён import CoreLocation (см. CLAUDE.md) —
// WatchRoundViewModel/WatchHoleView получают позицию только как
// Foundation-тип GeoFix (Models/Geo.swift), ничего не зная про CoreLocation.
// Трекинг стартует/стопится вместе с экраном лунки (WatchHoleView.onAppear/
// onDisappear) — батарея часов дороже телефонной, GPS не должен висеть
// постоянно. Разрешение запрашивается лениво, при первом startTracking().
import CoreLocation
import Foundation
import Observation

@Observable
final class WatchLocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = WatchLocationService()

    private let manager = CLLocationManager()

    /// refcount — тот же приём, что и в GeolocationService.startTracking()/
    /// stopTracking() на телефоне: экран лунки может появиться заново
    /// раньше, чем deinit/onDisappear предыдущего успеет остановить
    /// трекинг (переход лунка→лунка), поэтому булев флаг тут словил бы
    /// гонку — счётчик балансирует старт/стоп по парам.
    private var trackingCount = 0

    /// Последний известный фикс. Публикуется ТОЛЬКО на main (см.
    /// locationManager(_:didUpdateLocations:)) — @Observable ожидает
    /// изменения на main, как и обновления PhoneBridge.latestSnapshot.
    private(set) var lastFix: GeoFix?

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func startTracking() {
        trackingCount += 1
        guard trackingCount == 1 else { return }
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        trackingCount = max(0, trackingCount - 1)
        guard trackingCount == 0 else { return }
        manager.stopUpdatingLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // Разрешение могло прийти уже ПОСЛЕ requestWhenInUseAuthorization()
        // в startTracking() — доуправляем трекингом здесь, а не блокируем
        // startTracking() ожиданием колбэка.
        guard trackingCount > 0 else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = GeoFix(lat: location.coordinate.latitude,
                         lng: location.coordinate.longitude,
                         accuracy: location.horizontalAccuracy,
                         timestamp: location.timestamp)
        // Делегат CLLocationManager может прийти на фоновом потоке —
        // публикация в @Observable-свойство обязана идти через main (тот
        // же приём, что и у PhoneBridge для WCSessionDelegate).
        DispatchQueue.main.async { [weak self] in
            self?.lastFix = fix
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // На часах молча игнорируем: UI сам покажет «—» через гейт
        // возраста/точности (WatchRoundViewModel.greenDistanceMeters) —
        // отдельный error-стейт на маленьком экране не оправдан.
    }
}
