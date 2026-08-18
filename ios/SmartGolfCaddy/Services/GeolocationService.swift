// ios/SmartGolfCaddy/Services/GeolocationService.swift
// Обёртка CLLocationManager (when-in-use). Колбэки — на main.
import CoreLocation
import Foundation

struct GeoFix: Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double   // метры; < 0 = недостоверно
    let timestamp: Date    // из CLLocation.timestamp — для гейта устаревших фиксов
}

final class GeolocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    static let shared = GeolocationService()

    private let manager = CLLocationManager()
    private var onUpdate: ((Double, Double) -> Void)?
    private var onDenied: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    /// Последний известный фикс — читается дальномером в момент записи удара.
    /// Потокобезопасный доступ через отдельную очередь.
    private let fixQueue = DispatchQueue(label: "sgc.geo.fix")
    private var _lastFix: GeoFix?
    var lastFix: GeoFix? {
        fixQueue.sync { _lastFix }
    }

    // refcount: при replaceLast-переходе лунка→лунка новый экран стартует
    // трекинг раньше, чем deinit старого остановит его — булев флаг тут
    // ловит гонку (второй start проходит мимо guard, первый stop гасит
    // трекинг раньше времени). Счётчик балансирует старт/стоп по парам.
    private var trackingCount = 0

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
        trackingCount += 1
        guard trackingCount == 1 else { return }
        // Одноразовые колбэки поиска полей не должны переигрываться на каждом тике трекинга.
        onUpdate = nil
        onDenied = nil
        onError = nil
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        trackingCount = max(0, trackingCount - 1)
        guard trackingCount == 0 else { return }
        manager.stopUpdatingLocation()
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if trackingCount > 0 {
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
                         accuracy: location.horizontalAccuracy,
                         timestamp: location.timestamp)
        fixQueue.sync { self._lastFix = fix }
        // Вызвать onUpdate только для одноразовых запросов, не для непрерывного трекинга.
        if trackingCount == 0 {
            DispatchQueue.main.async { [weak self] in
                self?.onUpdate?(location.coordinate.latitude, location.coordinate.longitude)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?("Не удалось определить местоположение")
        }
    }
}
