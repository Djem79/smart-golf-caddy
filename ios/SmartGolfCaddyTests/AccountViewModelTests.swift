// ios/SmartGolfCaddyTests/AccountViewModelTests.swift
// Task 3, фаза 3d-1: удаление аккаунта. `deleter` подменяет сеть — образец
// JoinGameViewModelTests.
import XCTest
@testable import SmartGolfCaddy

final class AccountViewModelTests: XCTestCase {

    @MainActor
    func testSuccessClosesDialogAndClearsError() async {
        let model = AccountViewModel(deleter: {})
        model.showDeleteConfirm = true

        let success = await model.confirmDelete()

        XCTAssertTrue(success)
        XCTAssertFalse(model.showDeleteConfirm)
        XCTAssertNil(model.deleteError)
        XCTAssertFalse(model.deletingAccount)
    }

    @MainActor
    func testFailureShowsMessageAndDoesNotSignOut() async {
        struct Failure: Error {}
        let model = AccountViewModel(deleter: { throw Failure() })
        model.showDeleteConfirm = true

        let success = await model.confirmDelete()

        XCTAssertFalse(success)
        XCTAssertFalse(model.showDeleteConfirm)   // dialog closes either way
        // T4: compares against the current-locale string (not a hardcoded
        // Russian literal) so this test doesn't depend on, or leak, the
        // process's AppLocaleStore state.
        XCTAssertEqual(model.deleteError, AppLocaleStore.strings.profile.deleteAccountError)
        XCTAssertFalse(model.deletingAccount)     // re-enabled for retry
    }

    @MainActor
    func testNotReentrantWhileInFlight() async {
        var calls = 0
        let model = AccountViewModel(deleter: {
            calls += 1
            try? await Task.sleep(nanoseconds: 50_000_000)
        })
        async let first = model.confirmDelete()
        try? await Task.sleep(nanoseconds: 5_000_000)
        let second = await model.confirmDelete()
        _ = await first
        XCTAssertFalse(second)
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testRetryAfterFailureCanSucceed() async {
        var shouldFail = true
        struct Failure: Error {}
        let model = AccountViewModel(deleter: {
            if shouldFail { throw Failure() }
        })
        model.showDeleteConfirm = true
        let first = await model.confirmDelete()
        XCTAssertFalse(first)
        XCTAssertNotNil(model.deleteError)

        shouldFail = false
        model.showDeleteConfirm = true
        let second = await model.confirmDelete()
        XCTAssertTrue(second)
        XCTAssertNil(model.deleteError)
    }
}
