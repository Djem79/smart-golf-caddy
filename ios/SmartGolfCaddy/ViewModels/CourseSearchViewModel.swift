// ios/SmartGolfCaddy/ViewModels/CourseSearchViewModel.swift
import Foundation
import Observation

@Observable
@MainActor
final class CourseSearchViewModel {
    var searchText = ""
    var nearby: [CourseResult] = []
    var textResults: [CourseResult]?
    var loading = false
    var errorMessage: String?
    var geoDenied = false

    private var lat: Double?
    private var lng: Double?
    private var searchTask: Task<Void, Never>?

    var visible: [CourseResult] {
        if let textResults { return textResults }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return nearby }
        return nearby.filter {
            $0.name.lowercased().contains(query) || $0.vicinity.lowercased().contains(query)
        }
    }

    func start() {
        GeolocationService.shared.request(
            onUpdate: { [weak self] lat, lng in
                guard let self else { return }
                self.lat = lat
                self.lng = lng
                Task { await self.loadNearby() }
            },
            onError: { [weak self] message in
                self?.geoDenied = true
                self?.errorMessage = message
            }
        )
    }

    func loadNearby() async {
        guard let lat, let lng else { return }
        loading = true
        errorMessage = nil
        defer { loading = false }
        do {
            nearby = try await CoursesService.shared.findNearby(lat: lat, lng: lng)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Debounce 400мс; < 2 символов — сброс на локальный фильтр.
    func searchChanged() {
        searchTask?.cancel()
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else {
            textResults = nil
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.loading = true
            defer { self.loading = false }
            do {
                let results = try await CoursesService.shared.searchByText(
                    query, biasLat: self.lat, biasLng: self.lng
                )
                guard !Task.isCancelled else { return }
                self.textResults = results
            } catch {
                guard !Task.isCancelled else { return }
                self.textResults = []
            }
        }
    }
}
