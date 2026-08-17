import Foundation

enum ScoreDirection {
    case under, par, over
}

enum Score {
    static func color(_ delta: Int) -> String {
        if delta <= -2 { return "#FFD700" }
        if delta == -1 { return "#2E7D32" }
        if delta == 0 { return "#FFFFFF" }
        if delta == 1 { return "#EF6C00" }
        return "#C62828"
    }

    static func onColor(_ delta: Int) -> String {
        if delta <= -2 { return "#1A1C1C" }
        if delta == -1 { return "#FFFFFF" }
        if delta == 0 { return "#1A1C1C" }
        if delta == 1 { return "#1A1C1C" }
        return "#FFFFFF"
    }

    static func direction(_ delta: Int) -> ScoreDirection {
        if delta < 0 { return .under }
        if delta == 0 { return .par }
        return .over
    }

    static func label(_ delta: Int) -> String {
        if delta <= -2 { return "Eagle" }
        if delta == -1 { return "Birdie" }
        if delta == 0 { return "Par" }
        if delta == 1 { return "Bogey" }
        if delta == 2 { return "Double" }
        return "+\(delta)"
    }

    static func metersToYards(_ m: Int) -> Int {
        Int((Double(m) * 1.0936).rounded())
    }

    static func yardsToMeters(_ y: Int) -> Int {
        Int((Double(y) / 1.0936).rounded())
    }
}
