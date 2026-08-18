// ios/SmartGolfCaddyTests/MyBagViewModelTests.swift
import XCTest
@testable import SmartGolfCaddy

final class MyBagViewModelTests: XCTestCase {

    @MainActor
    private func makeModel() -> MyBagViewModel {
        let model = MyBagViewModel(persistBag: { _ in }, persistUnits: { _ in })
        // минимальный реальный профиль (bag nil → resolvedBag = дефолт, units .m),
        // но синхронизированный → мутации разрешены
        model.syncFromProfile(AppUser(uid: "u", data: ["name": "Тест"]))
        return model
    }

    @MainActor
    func testNilProfileShowsDefaultsButBlocksMutations() async {
        var persisted = 0
        let model = MyBagViewModel(persistBag: { _ in persisted += 1 }, persistUnits: { _ in })
        model.syncFromProfile(nil)
        XCTAssertEqual(model.bag, Clubs.defaultBag)
        XCTAssertEqual(model.units, .m)
        await model.toggle(id: "5W")
        XCTAssertEqual(persisted, 0)  // мутации до реального профиля не персистятся
        XCTAssertFalse(model.bag.first { $0.id == "5W" }!.enabled)  // и не применяются
    }

    @MainActor
    func testToggleFlipsEnabled() async {
        let model = makeModel()
        await model.toggle(id: "5W")
        XCTAssertTrue(model.bag.first { $0.id == "5W" }!.enabled)
        await model.toggle(id: "5W")
        XCTAssertFalse(model.bag.first { $0.id == "5W" }!.enabled)
    }

    @MainActor
    func testSetDistanceConvertsYards() async {
        let model = makeModel()
        model.units = .yd
        await model.setDistance(id: "7i", raw: "150")  // 150 ярдов → 137 м
        XCTAssertEqual(model.bag.first { $0.id == "7i" }!.distanceMeters, Score.yardsToMeters(150))
    }

    @MainActor
    func testSetDistanceIgnoresInvalid() async {
        let model = makeModel()
        let before = model.bag.first { $0.id == "7i" }!.distanceMeters
        await model.setDistance(id: "7i", raw: "abc")
        await model.setDistance(id: "7i", raw: "-5")
        XCTAssertEqual(model.bag.first { $0.id == "7i" }!.distanceMeters, before)
    }

    @MainActor
    func testAddCustomClubInsertsAtCategoryEnd() async {
        let model = makeModel()
        await model.addCustomClub(category: .wood, name: "Stealth 2", distance: 220)
        let woods = model.clubsInGroup(.wood)
        XCTAssertEqual(woods.last?.customName, "Stealth 2")
        XCTAssertTrue(woods.last!.id.hasPrefix("custom-"))
        XCTAssertTrue(woods.last!.enabled)
        // Кастомная НЕ в конце всего массива — паттерн веба (не позади паттера)
        XCTAssertNotEqual(model.bag.last?.customName, "Stealth 2")
    }

    @MainActor
    func testDeleteClub() async {
        let model = makeModel()
        await model.addCustomClub(category: .iron, name: "X", distance: 100)
        let id = model.clubsInGroup(.iron).last!.id
        await model.deleteClub(id: id)
        XCTAssertNil(model.bag.first { $0.id == id })
    }

    @MainActor
    func testMoveWithinCategory() async {
        let model = makeModel()
        // woods: Driver, 3W, 5W, Hybrid → переставить Driver в конец группы
        await model.moveClub(inCategory: .wood, from: IndexSet(integer: 0), to: 4)
        XCTAssertEqual(model.clubsInGroup(.wood).map(\.id), ["3W", "5W", "Hybrid", "Driver"])
        // айроны не задеты
        XCTAssertEqual(model.clubsInGroup(.iron).first?.id, "3i")
    }

    @MainActor
    func testPersistFailureShowsErrorAndKeepsOptimism() async {
        struct Boom: Error {}
        let model = MyBagViewModel(persistBag: { _ in throw Boom() }, persistUnits: { _ in })
        model.syncFromProfile(AppUser(uid: "u", data: ["name": "Тест"]))
        await model.toggle(id: "5W")
        XCTAssertEqual(model.errorMessage, "Не удалось сохранить изменения")
        XCTAssertTrue(model.bag.first { $0.id == "5W" }!.enabled)  // оптимизм не откатываем (веб-паритет)
    }
}
