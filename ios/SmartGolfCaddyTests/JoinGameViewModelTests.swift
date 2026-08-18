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

    @MainActor
    func testJoinIsNotReentrant() async {
        var calls = 0
        let model = JoinGameViewModel(joiner: { _, _ in
            calls += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
            return "r1"
        })
        model.setCode("ABC234")
        async let first = model.join(profile: nil)
        // Второй вызов, пока первый ещё в полёте, должен отбиться guard-ом
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await model.join(profile: nil)
        _ = await first
        XCTAssertNil(second)
        XCTAssertEqual(calls, 1)
    }
}
