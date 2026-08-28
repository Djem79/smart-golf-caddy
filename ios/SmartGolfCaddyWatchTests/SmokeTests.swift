import XCTest
@testable import SmartGolfCaddyWatch

/// Smoke-тест инфраструктуры watch-таргета (Task 1, Phase 3c): подтверждает,
/// что watchOS-таргет собирается, линкует общий Foundation-only домен
/// (Models/) по ссылке и тест-бандл может импортировать модуль приложения.
final class SmokeTests: XCTestCase {
    func testSharedModelsAreLinked() {
        // BagClub — часть общего Models/, подключённого в watch-таргет ссылкой.
        let club = BagClub(id: "Driver", customName: nil, distanceMeters: 230,
                            enabled: true, category: .wood, custom: nil)
        XCTAssertEqual(club.id, "Driver")
    }
}
