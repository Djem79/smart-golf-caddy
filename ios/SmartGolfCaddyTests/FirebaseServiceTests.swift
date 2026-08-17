// ios/SmartGolfCaddyTests/FirebaseServiceTests.swift
import FirebaseFirestore
import XCTest
@testable import SmartGolfCaddy

final class FirebaseServiceTests: XCTestCase {
    func testNormalizedDatesRecursion() {
        let ts = Timestamp(date: Date(timeIntervalSince1970: 1_000_000))
        let input: [String: Any] = [
            "createdAt": ts,
            "holes": [["shots": ["u1": ["updatedAt": ts]]]],
            "name": "x",
        ]
        let output = FirebaseService.normalizedDates(input) as! [String: Any]
        XCTAssertTrue(output["createdAt"] is Date)
        let holes = output["holes"] as! [[String: Any]]
        let shots = holes[0]["shots"] as! [String: [String: Any]]
        XCTAssertTrue(shots["u1"]!["updatedAt"] is Date)
        XCTAssertEqual(output["name"] as? String, "x")
    }
}
