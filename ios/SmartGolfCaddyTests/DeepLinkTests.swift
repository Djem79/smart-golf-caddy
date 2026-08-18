import XCTest
@testable import SmartGolfCaddy

final class DeepLinkTests: XCTestCase {
    @MainActor
    func testParsesAppSchemeAndWebLink() {
        XCTAssertEqual(RootView.joinCode(from: URL(string: "smartgolfcaddy://join/ABC234")!), "ABC234")
        XCTAssertEqual(RootView.joinCode(from: URL(string: "https://smart-golf-caddy.web.app/join/XYZ789")!), "XYZ789")
        XCTAssertNil(RootView.joinCode(from: URL(string: "smartgolfcaddy://other/ABC234")!))
        XCTAssertNil(RootView.joinCode(from: URL(string: "https://example.com/")!))
    }
}
