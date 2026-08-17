import SwiftUI

enum DSFont {
    static func regular(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Regular", size: size) }
    static func medium(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Medium", size: size) }
    static func semiBold(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-SemiBold", size: size) }
    static func bold(_ size: CGFloat) -> Font { .custom("PlayfairDisplay-Bold", size: size) }

    static let displayLG = bold(40)
    static let headlineLG = bold(32)
    static let headlineMD = semiBold(24)
    static let titleLG = semiBold(20)
    static let bodyMD = regular(16)
    static let labelLG = semiBold(14)
    static let labelMD = medium(12)
}
