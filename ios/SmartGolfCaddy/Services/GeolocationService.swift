// ios/SmartGolfCaddy/Services/GeolocationService.swift
// Обёртка CLLocationManager (when-in-use). Колбэки — на main.
import CoreLocation
import Foundation

final class GeolocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = GeolocationService()

    private let manager = CLLocationManager()
    private var onUpdate: ((Double, Double) -> Void)?
    private var onDenied: ((String) -> Void)?
    private var onError: ((String) -> Void)?

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

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
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
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(location.coordinate.latitude, location.coordinate.longitude)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?("Не удалось определить местоположение")
        }
    }
}
