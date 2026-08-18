// ios/SmartGolfCaddy/ViewModels/MyBagViewModel.swift
// Порт логики MyBag.tsx. Оптимистичные мутации: локально применяем сразу,
// затем персистим ВЕСЬ массив (веб-паритет updateBag); при ошибке показываем
// сообщение, оптимизм не откатываем (следующий снапшот профиля выправит).
import Foundation
import Observation

@Observable
@MainActor
final class MyBagViewModel {
    static let totalSlots = 14

    var bag: [BagClub] = Clubs.defaultBag
    var units: DistanceUnit = .m
    var saving = false
    var errorMessage: String?

    private let persistBag: ([BagClub]) async throws -> Void
    private let persistUnits: (DistanceUnit) async throws -> Void
    private var synced = false

    /// Прод-инициализатор: персист в Firestore текущего пользователя.
    convenience init() {
        self.init(
            persistBag: { bag in
                guard let uid = AuthService.currentUserId else { return }
                try await UsersService.updateBag(uid: uid, bag: bag)
            },
            persistUnits: { units in
                guard let uid = AuthService.currentUserId else { return }
                try await UsersService.updateUnits(uid: uid, units: units)
            }
        )
    }

    init(persistBag: @escaping ([BagClub]) async throws -> Void,
         persistUnits: @escaping (DistanceUnit) async throws -> Void) {
        self.persistBag = persistBag
        self.persistUnits = persistUnits
    }

    /// Синхронизация из снапшота профиля. Первый снапшот заполняет стейт;
    /// последующие применяем только когда нет незасейвленного оптимизма
    /// (saving == false), чтобы не затирать ввод пользователя.
    func syncFromProfile(_ profile: AppUser?) {
        guard !saving || !synced else { return }
        bag = Clubs.resolveBag(bag: profile?.bag, legacyClubs: profile?.legacyClubs)
        units = profile?.units ?? .m
        synced = true
    }

    var enabledCount: Int { bag.filter(\.enabled).count }

    func clubsInGroup(_ category: ClubCategory) -> [BagClub] {
        bag.filter { Clubs.category(of: $0) == category }
    }

    func distanceValue(for club: BagClub) -> Int {
        if Clubs.category(of: club) == .putter { return 0 }
        return units == .yd ? Score.metersToYards(club.distanceMeters) : club.distanceMeters
    }

    private func persist(_ next: [BagClub]) async {
        bag = next
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await persistBag(next)
        } catch {
            errorMessage = "Не удалось сохранить изменения"
        }
    }

    func toggle(id: String) async {
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.enabled.toggle()
            return patched
        })
    }

    func setName(id: String, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard let club = bag.first(where: { $0.id == id }),
              (club.customName ?? "") != trimmed else { return }
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.customName = trimmed.isEmpty ? nil : trimmed
            return patched
        })
    }

    func setDistance(id: String, raw: String) async {
        guard let num = Int(raw), num >= 0 else { return }
        let meters = units == .yd ? Score.yardsToMeters(num) : num
        guard let club = bag.first(where: { $0.id == id }),
              club.distanceMeters != meters else { return }
        await persist(bag.map { club in
            guard club.id == id else { return club }
            var patched = club
            patched.distanceMeters = meters
            return patched
        })
    }

    func changeUnits(_ newUnits: DistanceUnit) async {
        guard newUnits != units else { return }
        units = newUnits
        do {
            try await persistUnits(newUnits)
        } catch {
            // non-critical (веб-паритет)
        }
    }

    func addCustomClub(category: ClubCategory, name: String, distance: Int) async {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let meters = units == .yd ? Score.yardsToMeters(distance) : distance
        let newClub = BagClub(
            id: "custom-\(UUID().uuidString.prefix(8))",
            customName: trimmed,
            distanceMeters: meters,
            enabled: true,
            category: category,
            custom: true
        )
        // Вставка в конец категории (не в конец массива) — паттерн веба:
        // пикер клюшек в трекере идёт по порядку массива.
        var insertAt = bag.count
        for index in stride(from: bag.count - 1, through: 0, by: -1)
        where Clubs.category(of: bag[index]) == category {
            insertAt = index + 1
            break
        }
        var next = bag
        next.insert(newClub, at: insertAt)
        await persist(next)
    }

    func deleteClub(id: String) async {
        await persist(bag.filter { $0.id != id })
    }

    /// Перестановка внутри категории (List.onMove даёт индексы среза группы).
    func moveClub(inCategory category: ClubCategory, from source: IndexSet, to destination: Int) async {
        var group = clubsInGroup(category)
        group.move(fromOffsets: source, toOffset: destination)
        // Собираем bag заново: клюшки категории — в новом порядке, остальные на местах.
        var iterator = group.makeIterator()
        let next = bag.map { club in
            Clubs.category(of: club) == category ? iterator.next()! : club
        }
        await persist(next)
    }
}
