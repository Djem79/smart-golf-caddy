// ios/SmartGolfCaddyTests/JoinGameViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class JoinGameViewModelTests: XCTestCase {

    @MainActor
    func testCodeNormalizationAndSubmitGate() {
        let model = JoinGameViewModel(joiner: { _, _ in nil })
        model.setCode(" ab-c2 ")
        XCTAssertEqual(model.code, "ABC2")
        XCTAssertFalse(model.canSubmit)
        model.setCode("abc234xyz")
        XCTAssertEqual(model.code, "ABC234")   // обрезано до 6
        XCTAssertTrue(model.canSubmit)
    }

    @MainActor
    func testJoinNotFoundShowsMessage() async {
        let model = JoinGameViewModel(joiner: { _, _ in nil })
        model.setCode("ABC234")
        let roundId = await model.join(profile: nil)
        XCTAssertNil(roundId)
        XCTAssertEqual(model.errorMessage,
                       "Лобби с таким кодом не найдено. Проверьте код или попросите хоста создать новое.")
    }

    @MainActor
    func testJoinSuccessReturnsRoundId() async {
        let model = JoinGameViewModel(joiner: { code, _ in code == "ABC234" ? "r1" : nil })
        model.setCode("abc234")
        let roundId = await model.join(profile: nil)
        XCTAssertEqual(roundId, "r1")
        XCTAssertNil(model.errorMessage)
    }

    @MainActor
    func testAutoJoinRunsOnce() async {
        var calls = 0
        let model = JoinGameViewModel(joiner: { _, _ in calls += 1; return "r1" })
        _ = await model.autoJoinIfNeeded(initial: "ABC234", profile: nil)
        _ = await model.autoJoinIfNeeded(initial: "ABC234", profile: nil)
        XCTAssertEqual(calls, 1)
    }
}
