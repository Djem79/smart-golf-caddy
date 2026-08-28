// ios/SmartGolfCaddy/Models/GreenMarks.swift
// Краудсорс-метки гринов: каждый игрок хранит СВОИ координаты гринов поля,
// приложение усредняет метки всех игроков. Так одна ошибочная отметка не
// портит поле остальным, а несколько отметок повышают точность.
import Foundation

struct GreenMark: Equatable {
    let lat: Double
    let lng: Double
}

struct GreenMarkSet: Equatable {
    var holes: [Int: GreenMark]

    init(holes: [Int: GreenMark]) {
        self.holes = holes
    }

    init?(data: [String: Any]) {
        guard let raw = data["holes"] as? [String: [String: Any]] else { return nil }
        var parsed: [Int: GreenMark] = [:]
        for (key, value) in raw {
            guard let hole = Int(key),
                  let lat = (value["lat"] as? NSNumber)?.doubleValue,
                  let lng = (value["lng"] as? NSNumber)?.doubleValue else { continue }
            parsed[hole] = GreenMark(lat: lat, lng: lng)
        }
        holes = parsed
    }

    var firestoreData: [String: Any] {
        var mapped: [String: [String: Any]] = [:]
        for (hole, mark) in holes {
            mapped[String(hole)] = ["lat": mark.lat, "lng": mark.lng]
        }
        return ["holes": mapped]
    }
}

enum Greens {
    /// Дефолтная заглушка `RoundSetupViewModel.effectiveName`, которую
    /// пользователь не вводил сам — не идентифицирует физическое поле.
    private static let unnamedCoursePlaceholder = "поле для гольфа"

    /// Стабильный ключ поля для меток гринов. Для полей из поиска —
    /// placeId. Для введённых вручную id уникален на раунд
    /// (`custom-<UUID>`), поэтому ключом служит нормализованное название —
    /// иначе метки никогда бы не переиспользовались. nil = поле не
    /// идентифицировано (ручной раунд без названия): метки не собираем,
    /// иначе грины разных физических полей смешались бы под одним ключом
    /// «поле для гольфа».
    static func courseKey(courseId: String, courseName: String) -> String? {
        if !courseId.hasPrefix("custom-"), !courseId.isEmpty { return courseId }
        let normalized = courseName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        // Слеш — разделитель сегментов пути Firestore, поэтому любые
        // недопустимые символы заменяем на «-», а пустое имя заменяем
        // плейсхолдером, иначе получится пустой сегмент пути.
        let sanitized = String(normalized.map { char in
            (char == "/" || char == "\\" || char == "." || char == "#" || char == "$"
             || char == "[" || char == "]") ? "-" : char
        })
        let bounded = String(sanitized.prefix(100))
        // Дефолтное имя-заглушка не идентифицирует поле.
        guard !bounded.isEmpty, bounded != unnamedCoursePlaceholder else { return nil }
        return "name:\(bounded)"
    }

    /// Среднее координат по всем игрокам, отметившим эту лунку.
    static func average(_ sets: [GreenMarkSet], hole: Int) -> GreenMark? {
        let marks = sets.compactMap { $0.holes[hole] }
        guard !marks.isEmpty else { return nil }
        let lat = marks.reduce(0.0) { $0 + $1.lat } / Double(marks.count)
        let lng = marks.reduce(0.0) { $0 + $1.lng } / Double(marks.count)
        return GreenMark(lat: lat, lng: lng)
    }

    static func distanceMeters(from fix: GeoFix, to green: GreenMark) -> Int {
        Int(GeoMath.haversineMetres(fix.lat, fix.lng, green.lat, green.lng).rounded())
    }
}
