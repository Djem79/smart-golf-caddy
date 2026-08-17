import XCTest
import SwiftUI
@testable import SmartGolfCaddy

final class DesignSystemTests: XCTestCase {
    func testPlayfairNamedInstancesAvailable() {
        // Именованные инстансы variable-шрифта видны UIKit по PostScript-имени.
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-Regular", size: 16))
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-SemiBold", size: 16))
        XCTAssertNotNil(UIFont(name: "PlayfairDisplay-Bold", size: 16))
    }

    func testHexColorParsing() {
        XCTAssertEqual(Color(hex: "#00450D"), DSColor.primary)
    }

    func testTouchTarget() {
        XCTAssertEqual(DS.touchTarget, 48)
    }
}
