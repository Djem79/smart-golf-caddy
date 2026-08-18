import XCTest
@testable import SmartGolfCaddy

final class QRCodeTests: XCTestCase {
    func testGeneratesImageForCode() throws {
        let image = try XCTUnwrap(QRCode.image(for: "smartgolfcaddy://join/ABC234"))
        XCTAssertGreaterThan(image.size.width, 0)
        XCTAssertGreaterThan(image.size.height, 0)
    }

    func testEmptyStringGivesNil() {
        XCTAssertNil(QRCode.image(for: ""))
    }
}
