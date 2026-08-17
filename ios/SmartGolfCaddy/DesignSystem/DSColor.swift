import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}

enum DSColor {
    static let primary = Color(hex: "#00450D")
    static let primaryContainer = Color(hex: "#1B5E20")
    static let onPrimary = Color(hex: "#FFFFFF")
    static let inversePrimary = Color(hex: "#91D78A")
    static let secondary = Color(hex: "#5E604D")
    static let secondaryContainer = Color(hex: "#E1E1C9")
    static let onSecondary = Color(hex: "#FFFFFF")
    static let tertiary = Color(hex: "#2D3D45")
    static let tertiaryContainer = Color(hex: "#44545C")
    static let onTertiary = Color(hex: "#FFFFFF")
    static let surface = Color(hex: "#F9F9F9")
    static let surfaceDim = Color(hex: "#DADADA")
    static let surfaceContainerLowest = Color(hex: "#FFFFFF")
    static let surfaceContainerLow = Color(hex: "#F3F3F4")
    static let surfaceContainer = Color(hex: "#EEEEEE")
    static let surfaceContainerHigh = Color(hex: "#E8E8E8")
    static let onSurface = Color(hex: "#1A1C1C")
    static let onSurfaceVariant = Color(hex: "#41493E")
    static let outline = Color(hex: "#717A6D")
    static let outlineVariant = Color(hex: "#C0C9BB")
    static let error = Color(hex: "#BA1A1A")
    static let errorContainer = Color(hex: "#FFDAD6")
    static let onError = Color(hex: "#FFFFFF")
}
