// ios/SmartGolfCaddyTests/GreenMarksTests.swift
import XCTest
@testable import SmartGolfCaddy

final class GreenMarksTests: XCTestCase {

    func testCourseKeyUsesPlaceIdWhenAvailable() {
        XCTAssertEqual(Greens.courseKey(courseId: "ChIJp1HB", courseName: "Krylatskoye"), "ChIJp1HB")
    }

    func testCourseKeyFallsBackToNormalizedNameForManualCourses() {
        // Ручной ввод даёт уникальный на раунд id — метки бы не переиспользовались.
        let a = Greens.courseKey(courseId: "custom-ABC123", courseName: "  Dubai   Hills  ")
        let b = Greens.courseKey(courseId: "custom-XYZ789", courseName: "dubai hills")
        XCTAssertEqual(a, b)
        XCTAssertTrue(a.hasPrefix("name:"))
    }

    func testAverageOfMarks() {
        let sets = [
            GreenMarkSet(holes: [1: GreenMark(lat: 55.700, lng: 37.400)]),
            GreenMarkSet(holes: [1: GreenMark(lat: 55.702, lng: 37.402)]),
            GreenMarkSet(holes: [2: GreenMark(lat: 55.710, lng: 37.410)]),
        ]
        let averaged = Greens.average(sets, hole: 1)
        XCTAssertEqual(averaged?.lat ?? 0, 55.701, accuracy: 0.0001)
        XCTAssertEqual(averaged?.lng ?? 0, 37.401, accuracy: 0.0001)
        XCTAssertNil(Greens.average(sets, hole: 3))
    }

    func testDistanceMeters() {
        let fix = GeoFix(lat: 55.700000, lng: 37.400000, accuracy: 5, timestamp: Date())
        let green = GreenMark(lat: 55.701000, lng: 37.400000)   // ~111 м на север
        XCTAssertEqual(Double(Greens.distanceMeters(from: fix, to: green)), 111, accuracy: 3)
    }

    func testFirestoreRoundTrip() {
        let set = GreenMarkSet(holes: [1: GreenMark(lat: 55.7, lng: 37.4),
                                       9: GreenMark(lat: 55.8, lng: 37.5)])
        let restored = GreenMarkSet(data: set.firestoreData)
        XCTAssertEqual(restored, set)
    }

    func testCourseKeySanitizesPathBreakingCharacters() {
        let key = Greens.courseKey(courseId: "custom-1", courseName: "Golf Club / North #2")
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains("#"))
        XCTAssertEqual(key, "name:golf club - north -2")
    }

    func testCourseKeyForEmptyNameIsStable() {
        XCTAssertEqual(Greens.courseKey(courseId: "custom-1", courseName: "   "), "name:unnamed")
    }
}
