// ios/SmartGolfCaddyWatchTests/WatchRootViewTests.swift
// Тест чистой функции WatchRootView.staleSyncFailure — единственная часть
// Fix 12 (живое ревью Task 4), которую можно проверить юнит-тестом: сама
// View (SwiftUI, .task { }-обсёрвер) в этом проекте не тестируется
// (нет ViewInspector), поэтому решение "нужно ли показать баннер о
// отклонённом ударе ЧУЖОГО (не текущего) раунда" вынесено из closure в
// static-функцию.
//
// Трасса Fix 12: удар записан на часах, батч не долетел, телефон
// завершает раунд, связь восстанавливается, сервер отвергает запись
// (round уже finished) — квитанция accepted: false приходит на часы
// ПОЗЖЕ, когда WatchRoundViewModel уже может показывать другой раунд
// (или не существовать вовсе). WatchRoundViewModel.handleSyncFailed
// фильтрует такую квитанцию по roundId == snapshot?.roundId и
// заслуженно её игнорирует (это НЕ её раунд) — но кто-то ДОЛЖЕН довести
// сигнал до игрока, иначе удар теряется молча. staleSyncFailure — эта
// точка: срабатывает ИМЕННО когда roundId квитанции отличается от
// текущего (включая nil — нет активного раунда на экране вовсе).
import XCTest
@testable import SmartGolfCaddyWatch

final class WatchRootViewTests: XCTestCase {

    // MARK: - Разные раунды → баннер обязателен (иначе сигнал теряется
    // молча, ровно то, что Fix 12 обязан исключить)

    func testDifferentRoundIdProducesBanner() {
        let failure = WatchRootView.staleSyncFailure(
            forRoundId: "round-old", holeNumber: 18, currentRoundId: "round-new"
        )
        XCTAssertEqual(failure, WatchRootView.StaleSyncFailure(roundId: "round-old", holeNumber: 18))
    }

    /// Нет активного раунда на экране (VM ещё не создана / вернулись на
    /// плейсхолдер) — квитанция ЛЮБОГО раунда обязана быть показана, а не
    /// молча проигнорирована как "нет текущего снимка — некуда её
    /// приткнуть".
    func testNilCurrentRoundIdProducesBanner() {
        let failure = WatchRootView.staleSyncFailure(
            forRoundId: "round-old", holeNumber: 18, currentRoundId: nil
        )
        XCTAssertEqual(failure, WatchRootView.StaleSyncFailure(roundId: "round-old", holeNumber: 18))
    }

    // MARK: - Тот же раунд → nil (уже показано через
    // WatchHoleView/currentHoleSyncFailed, дублировать не нужно)

    func testSameRoundIdReturnsNil() {
        let failure = WatchRootView.staleSyncFailure(
            forRoundId: "round-current", holeNumber: 5, currentRoundId: "round-current"
        )
        XCTAssertNil(failure)
    }
}
