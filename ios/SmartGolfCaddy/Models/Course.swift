// ios/SmartGolfCaddy/Models/Course.swift
import Foundation

struct CourseResult: Equatable, Identifiable {
    let placeId: String
    let name: String
    let vicinity: String
    let rating: Double?
    let userRatingsTotal: Int?
    let lat: Double
    let lng: Double
    let distanceKm: Double
    var id: String { placeId }
}
