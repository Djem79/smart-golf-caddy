// ios/SmartGolfCaddyWatch/DesignSystem/WatchColor.swift
// Цветовые токены под ТЁМНЫЙ фон. watchOS-экраны всегда рендерятся на
// чёрном (OLED) — общие DSColor из SmartGolfCaddy/DesignSystem заточены под
// СВЕТЛЫЙ фон компаньона (onSurface ≈ #1A1C1C, onSurfaceVariant — тёмный
// зелёно-серый): на чёрном они нечитаемы или почти не видны. Для текста и
// фона на часах используем этот отдельный набор; DSColor.primary остаётся
// уместен как ЗАЛИВКА кнопки (тёмно-зелёная плашка с белым текстом читаема
// независимо от фона экрана), но не как цвет текста поверх чёрного.
import SwiftUI

enum WatchColor {
    static let background = Color.black
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.65)
    /// Акцент — светло-зелёный (DSColor.inversePrimary), контрастен на чёрном.
    static let accent = DSColor.inversePrimary
    /// Индикатор несинхронизированных ударов.
    static let pending = Color(hex: "#FFB74D")
}
