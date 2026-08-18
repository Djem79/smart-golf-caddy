// ios/SmartGolfCaddy/Services/ShotRangefinder.swift
// Автоматический замер дистанции удара: позиция запоминается в момент
// записи удара, дистанция считается при записи следующего. Точка живёт в
// файле (переживает перезапуск), привязана к слоту round:hole:uid.
import Foundation

final class ShotRangefinder: @unchecked Sendable {

    static let shared = ShotRangefinder(
        storeURL: ShotRangefinder.defaultStoreURL(),
        fixProvider: { GeolocationService.shared.lastFix }
    )

    /// Худшая точность фикса, при которой замер считается достоверным.
    static let accuracyLimitMeters = 25.0
    /// Разумные границы длины удара — вне их значение считаем неизвестным.
    static let minMeters = 3.0
    static let maxMeters = 600.0

    private struct Mark: Codable {
        var lat: Double
        var lng: Double
        var shotIndex: Int
    }

    private let storeURL: URL
    private let fixProvider: () -> GeoFix?
    private let ioQueue = DispatchQueue(label: "sgc.rangefinder.io")

    init(storeURL: URL, fixProvider: @escaping () -> GeoFix?) {
        self.storeURL = storeURL
        self.fixProvider = fixProvider
    }

    static func isUsable(_ fix: GeoFix?) -> Bool {
        guard let fix else { return false }
        return fix.accuracy > 0 && fix.accuracy <= accuracyLimitMeters
    }

    static func sanitize(_ meters: Double) -> Int {
        guard meters >= minMeters, meters <= maxMeters else { return 0 }
        return Int(meters.rounded())
    }

    func markShot(roundId: String, holeIndex: Int, targetUid: String, shotIndex: Int) {
        guard let fix = fixProvider(), Self.isUsable(fix) else { return }
        mutate { $0[Self.key(roundId, holeIndex, targetUid)] = Mark(lat: fix.lat, lng: fix.lng, shotIndex: shotIndex) }
    }

    func measure(roundId: String, holeIndex: Int, targetUid: String) -> (previousIndex: Int, meters: Int)? {
        guard let fix = fixProvider(), Self.isUsable(fix) else { return nil }
        guard let mark = load()[Self.key(roundId, holeIndex, targetUid)] else { return nil }
        let meters = CoursesService.haversineMetres(mark.lat, mark.lng, fix.lat, fix.lng)
        return (mark.shotIndex, Self.sanitize(meters))
    }

    func clear(roundId: String, holeIndex: Int, targetUid: String) {
        mutate { $0.removeValue(forKey: Self.key(roundId, holeIndex, targetUid)) }
    }

    // MARK: хранилище

    private static func key(_ roundId: String, _ holeIndex: Int, _ targetUid: String) -> String {
        "\(roundId):\(holeIndex):\(targetUid)"
    }

    private func load() -> [String: Mark] {
        ioQueue.sync {
            guard let data = try? Data(contentsOf: storeURL) else { return [:] }
            return (try? JSONDecoder().decode([String: Mark].self, from: data)) ?? [:]
        }
    }

    private func mutate(_ block: (inout [String: Mark]) -> Void) {
        ioQueue.sync {
            var map: [String: Mark] = {
                guard let data = try? Data(contentsOf: storeURL) else { return [:] }
                return (try? JSONDecoder().decode([String: Mark].self, from: data)) ?? [:]
            }()
            block(&map)
            if let data = try? JSONEncoder().encode(map) {
                try? data.write(to: storeURL, options: .atomic)
            }
        }
    }

    private static func defaultStoreURL() -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("shot-marks-v1.json")
    }
}
