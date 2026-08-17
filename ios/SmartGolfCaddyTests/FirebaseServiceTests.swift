// ios/SmartGolfCaddyTests/FirebaseServiceTests.swift
//
// Timestamp берём из ObjC-рантайма хост-приложения (FIRTimestamp), НЕ
// линкуя FirebaseFirestore в тест-таргет: вторая копия FirebaseCore из-за
// такой линковки роняла приложение (FIRIllegalStateException, см. #14464
// и шапку project.yml).
import XCTest
@testable import SmartGolfCaddy

final class FirebaseServiceTests: XCTestCase {
    private func makeTimestamp(_ date: Date) throws -> NSObject {
        let tsClass = try XCTUnwrap(NSClassFromString("FIRTimestamp") as? NSObject.Type)
        let result = try XCTUnwrap(
            tsClass.perform(NSSelectorFromString("timestampWithDate:"), with: date)
        )
        return try XCTUnwrap(result.takeUnretainedValue() as? NSObject)
    }

    func testNormalizedDatesRecursion() throws {
        let ts = try makeTimestamp(Date(timeIntervalSince1970: 1_000_000))
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
