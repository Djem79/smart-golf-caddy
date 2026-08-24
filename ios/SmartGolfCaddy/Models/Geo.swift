// ios/SmartGolfCaddy/Models/Geo.swift
// Foundation-only геометрия: живёт в Models, а не в Services/
// (CoreLocation), потому что подключается по ссылке в watch-таргет
// (Phase 3c) — там нет Services/. GreenMarks.distanceMeters использует
// оба типа ниже, поэтому им нельзя оставаться в Services.
import Foundation

/// Снимок позиции игрока в момент замера (из CLLocation на iOS-стороне).
struct GeoFix: Equatable {
    let lat: Double
    let lng: Double
    let accuracy: Double   // метры; < 0 = недостоверно
    let timestamp: Date    // из CLLocation.timestamp — для гейта устаревших фиксов
}

enum GeoMath {
    /// Дистанция между двумя точками по формуле гаверсинуса, метры.
    static func haversineMetres(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        let r = 6371000.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLng = (lng2 - lng1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLng / 2) * sin(dLng / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Единое место для порогов достоверности GPS-фикса — используется И
/// дальномером удара на телефоне (`ShotRangefinder`), И дистанцией до
/// грина на обеих платформах (`HoleTrackerViewModel` на телефоне,
/// `WatchRoundViewModel` на часах). До Фазы 3c Task 6 эти же числа жили
/// ДВУМЯ копиями литералов, связанными только комментариями «синхронизировать
/// вручную» — живёт здесь ровно потому, что `Models/` подключён ссылкой в
/// оба таргета (в отличие от `Services/`, недоступного часам).
enum GeoGates {
    /// Худшая точность фикса (метры), при которой замер ещё считается
    /// достоверным.
    static let accuracyLimitMeters = 25.0
    /// Максимальный возраст фикса (сек). Экран блокируется →
    /// CLLocationManager стопится, `lastFix` замирает; без гейта замер
    /// после разблокировки считает дистанцию от точки многоминутной
    /// давности.
    static let maxFixAgeSeconds: TimeInterval = 90
    /// Верхняя граница правдоподобной дистанции до грина, метры — больше
    /// не бывает: это чужое поле или мусорная метка.
    static let maxGreenDistanceMeters = 800

    /// Годен ли фикс для замера — общий гейт для дальномера удара и
    /// дистанции до грина.
    static func isUsable(_ fix: GeoFix?) -> Bool {
        guard let fix else { return false }
        guard Date().timeIntervalSince(fix.timestamp) <= maxFixAgeSeconds else { return false }
        return fix.accuracy > 0 && fix.accuracy <= accuracyLimitMeters
    }

    /// Клэмп дистанции до грина: вне 0…maxGreenDistanceMeters считаем
    /// недостоверным (nil), а не показываем выброс.
    static func clampGreenDistance(_ meters: Int) -> Int? {
        (0...maxGreenDistanceMeters).contains(meters) ? meters : nil
    }
}
