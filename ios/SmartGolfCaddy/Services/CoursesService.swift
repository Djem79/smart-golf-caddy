// ios/SmartGolfCaddy/Services/CoursesService.swift
// Порт src/services/courses.ts — Places API (New), REST. Ключ отдельный,
// с iOS-bundle-restriction (веб-ключ с HTTP-referrer здесь не работает).
import Foundation

enum CourseFetchError: LocalizedError {
    case config
    case network(String)
    case denied(String)
    case quota
    case invalid
    case http(Int)

    var errorDescription: String? {
        let errors = AppLocaleStore.strings.courseSearch.errors
        switch self {
        case .config: return errors.apiKeyMissing
        case .network: return errors.network
        case .denied: return errors.denied
        case .quota: return errors.quota
        case .invalid: return errors.invalid
        case .http(let code): return "Places API HTTP \(code)"
        }
    }
}

final class CoursesService: @unchecked Sendable {
    static let shared = CoursesService(
        apiKey: Bundle.main.object(forInfoDictionaryKey: "GooglePlacesAPIKey") as? String
    )

    private let apiKey: String?
    private let transport: (URLRequest) async throws -> (Data, URLResponse)

    init(apiKey: String?,
         transport: @escaping (URLRequest) async throws -> (Data, URLResponse) = { request in
             try await URLSession.shared.data(for: request)
         }) {
        // Пустая строка/плейсхолдер = ключа нет.
        let cleaned = apiKey?.trimmingCharacters(in: .whitespaces)
        self.apiKey = (cleaned?.isEmpty ?? true) || cleaned == "placeholder" ? nil : cleaned
        self.transport = transport
    }

    private struct PlacesResponse: Decodable {
        struct Place: Decodable {
            struct DisplayName: Decodable { let text: String? }
            struct Location: Decodable { let latitude: Double?; let longitude: Double? }
            let id: String?
            let displayName: DisplayName?
            let formattedAddress: String?
            let rating: Double?
            let userRatingCount: Int?
            let location: Location?
        }
        struct APIError: Decodable { let message: String? }
        let places: [Place]?
        let error: APIError?
    }

    private static let fieldMask = [
        "places.id", "places.displayName", "places.formattedAddress",
        "places.rating", "places.userRatingCount", "places.location",
    ].joined(separator: ",")

    func findNearby(lat: Double, lng: Double) async throws -> [CourseResult] {
        let body: [String: Any] = [
            "includedTypes": ["golf_course"],
            "maxResultCount": 20,
            "locationRestriction": [
                "circle": ["center": ["latitude": lat, "longitude": lng], "radius": 20000.0],
            ],
        ]
        return try await request(
            url: "https://places.googleapis.com/v1/places:searchNearby",
            body: body, originLat: lat, originLng: lng
        )
    }

    func searchByText(_ query: String, biasLat: Double?, biasLng: Double?) async throws -> [CourseResult] {
        var body: [String: Any] = [
            "textQuery": query,
            "includedType": "golf_course",
            "maxResultCount": 20,
        ]
        if let biasLat, let biasLng {
            body["locationBias"] = [
                "circle": ["center": ["latitude": biasLat, "longitude": biasLng], "radius": 50000.0],
            ]
        }
        return try await request(
            url: "https://places.googleapis.com/v1/places:searchText",
            body: body, originLat: biasLat, originLng: biasLng
        )
    }

    private func request(url: String, body: [String: Any],
                         originLat: Double?, originLng: Double?) async throws -> [CourseResult] {
        guard let apiKey else { throw CourseFetchError.config }
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(Self.fieldMask, forHTTPHeaderField: "X-Goog-FieldMask")
        // Обязателен для ключей с iOS-app-restriction: без него Google
        // отвечает 403 «Requests from this iOS client <empty> are blocked».
        request.setValue(Bundle.main.bundleIdentifier ?? "com.dzhambulat.smartgolfcaddy",
                         forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch {
            throw CourseFetchError.network(String(describing: error))
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 {
            let detail = (try? JSONDecoder().decode(PlacesResponse.self, from: data))?.error?.message ?? ""
            switch status {
            case 403: throw CourseFetchError.denied(detail)
            case 429: throw CourseFetchError.quota
            case 400: throw CourseFetchError.invalid
            default: throw CourseFetchError.http(status)
            }
        }

        let parsed = try JSONDecoder().decode(PlacesResponse.self, from: data)
        return (parsed.places ?? []).map { place in
            let placeLat = place.location?.latitude ?? originLat ?? 0
            let placeLng = place.location?.longitude ?? originLng ?? 0
            let distanceKm: Double
            if let originLat, let originLng {
                distanceKm = (Self.haversineMetres(originLat, originLng, placeLat, placeLng) / 100).rounded() / 10
            } else {
                distanceKm = 0
            }
            return CourseResult(
                placeId: place.id ?? "",
                name: place.displayName?.text ?? AppLocaleStore.strings.courseSearch.courseFallbackName,
                vicinity: place.formattedAddress ?? "",
                rating: place.rating,
                userRatingsTotal: place.userRatingCount,
                lat: placeLat, lng: placeLng,
                distanceKm: distanceKm
            )
        }
    }

    static func haversineMetres(_ lat1: Double, _ lng1: Double, _ lat2: Double, _ lng2: Double) -> Double {
        GeoMath.haversineMetres(lat1, lng1, lat2, lng2)
    }
}
