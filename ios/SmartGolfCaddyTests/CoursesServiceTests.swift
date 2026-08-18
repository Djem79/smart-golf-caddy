import XCTest
@testable import SmartGolfCaddy

final class CoursesServiceTests: XCTestCase {

    private func makeService(
        status: Int = 200,
        body: String,
        apiKey: String? = "test-key",
        captured: ((URLRequest) -> Void)? = nil
    ) -> CoursesService {
        CoursesService(apiKey: apiKey) { request in
            captured?(request)
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            return (body.data(using: .utf8)!, response)
        }
    }

    func testFindNearbyParsesPlaces() async throws {
        let body = """
        {"places":[{"id":"p1","displayName":{"text":"Сколково Гольф"},"formattedAddress":"Москва",
        "rating":4.7,"userRatingCount":120,"location":{"latitude":55.68,"longitude":37.38}}]}
        """
        let service = makeService(body: body)
        let results = try await service.findNearby(lat: 55.7, lng: 37.4)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].placeId, "p1")
        XCTAssertEqual(results[0].name, "Сколково Гольф")
        XCTAssertEqual(results[0].rating, 4.7)
        XCTAssertEqual(results[0].distanceKm, 2.5, accuracy: 1.5)  // haversine ~2-3 км
    }

    func testMissingKeyThrowsConfig() async {
        let service = makeService(body: "{}", apiKey: nil)
        do {
            _ = try await service.findNearby(lat: 1, lng: 1)
            XCTFail("ожидали ошибку")
        } catch let error as CourseFetchError {
            XCTAssertEqual(error.errorDescription, "API ключ Google Places не настроен")
        } catch { XCTFail("не тот тип") }
    }

    func testDeniedMapsTo403() async {
        let service = makeService(status: 403, body: #"{"error":{"message":"key restricted"}}"#)
        do {
            _ = try await service.findNearby(lat: 1, lng: 1)
            XCTFail("ожидали ошибку")
        } catch let error as CourseFetchError {
            if case .denied(let detail) = error {
                XCTAssertTrue(detail.contains("key restricted"))
            } else { XCTFail("не denied: \(error)") }
        } catch { XCTFail("не тот тип") }
    }

    func testSearchByTextSendsQueryAndBias() async throws {
        var sentBody: [String: Any] = [:]
        let service = makeService(body: #"{"places":[]}"#) { request in
            if let data = request.httpBody {
                sentBody = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            }
        }
        _ = try await service.searchByText("гольф", biasLat: 55.7, biasLng: 37.4)
        XCTAssertEqual(sentBody["textQuery"] as? String, "гольф")
        XCTAssertNotNil(sentBody["locationBias"])
    }
}
