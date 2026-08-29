import XCTest
@testable import SmartGolfCaddy

final class RoundSetupViewModelTests: XCTestCase {
    @MainActor
    func testEffectiveNameTrimAndFallback() {
        let model = RoundSetupViewModel()
        model.courseName = "   "
        XCTAssertEqual(model.effectiveName, AppLocaleStore.strings.courseSearch.courseFallbackName)
        model.courseName = "  Сколково  "
        XCTAssertEqual(model.effectiveName, "Сколково")
    }
}
