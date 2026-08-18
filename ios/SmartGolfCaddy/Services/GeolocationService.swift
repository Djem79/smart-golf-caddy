// ios/SmartGolfCaddy/Services/GeolocationService.swift
// Обёртка CLLocationManager (when-in-use). Колбэки — на main.
import CoreLocation
import Foundation

struct GeoFix: Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double   // метры; < 0 = недостоверно
}

final class GeolocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = GeolocationService()

    private let manager = CLLocationManager()
    private var onUpdate: ((Double, Double) -> Void)?
    private var onDenied: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    /// Последний известный фикс — читается дальномером в момент записи удара.
    private(set) var lastFix: GeoFix?
    private var tracking = false

    override private init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func request(onUpdate: @escaping (Double, Double) -> Void,
                 onDenied: @escaping (String) -> Void,
                 onError: @escaping (String) -> Void) {
        self.onUpdate = onUpdate
        self.onDenied = onDenied
        self.onError = onError
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            DispatchQueue.main.async {
                onDenied("Доступ к геолокации запрещён. Разрешите его в Настройках.")
            }
        default:
            manager.requestLocation()
        }
    }

    /// Непрерывный трекинг на время экрана лунки. Точность «до 10 метров»
    /// достаточна для замера ударов и экономнее полной.
    func startTracking() {
        guard !tracking else { return }
        tracking = true
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        guard tracking else { return }
        tracking = false
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if tracking {
                manager.startUpdatingLocation()
            } else {
                manager.requestLocation()
            }
        case .denied, .restricted:
            DispatchQueue.main.async { [weak self] in
                self?.onDenied?("Доступ к геолокации запрещён. Разрешите его в Настройках.")
            }
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let fix = GeoFix(lat: location.coordinate.latitude,
                         lng: location.coordinate.longitude,
                         accuracy: location.horizontalAccuracy)
        DispatchQueue.main.async { [weak self] in
            self?.lastFix = fix
            self?.onUpdate?(location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?("Не удалось определить местоположение")
        }
    }
}
