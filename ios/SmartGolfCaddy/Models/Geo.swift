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
