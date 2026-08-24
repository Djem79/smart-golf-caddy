// ios/SmartGolfCaddyWatch/ViewModels/WatchRoundViewModel.swift
// Чистая логика экрана лунки на часах. НИКАКИХ WatchConnectivity-вызовов —
// снимок подаётся снаружи (init/apply), отправка батчей — задача Task 4.
// import WatchConnectivity запрещён в этом файле (см. CLAUDE.md).
import Foundation
import Observation

@Observable
@MainActor
final class WatchRoundViewModel {

    private(set) var snapshot: WatchRoundSnapshot?

    /// Номер активной на часах лунки. Управляется ТОЛЬКО навигацией на
    /// часах (nextHole/previousHole) — apply(snapshot:) намеренно НЕ
    /// перескакивает сюда за activeHoleNumber телефона: игрок может листать
    /// лунки на часах (посмотреть пар/дистанцию), не двигая прогресс на
    /// телефоне, и это не должно дёргать текущий экран из-под пальца.
    /// Стартовое значение — единственное место, где activeHoleNumber снимка
    /// используется.
    private(set) var holeNumber: Int = 1

    /// Клюшки ударов по лункам — ЛОКАЛЬНОЕ состояние часов, ключ — номер
    /// лунки. При первом появлении лунки в снимке (init ИЛИ apply) сюда
    /// подставляются плейсхолдеры по числу уже подтверждённых сервером
    /// ударов (myShots) — это даёт корректный стартовый счёт при
    /// продолжении раунда, начатого на телефоне. Название клюшки для чужих
    /// (не введённых на часах) ударов неизвестно — плейсхолдер: первая
    /// клюшка из сумки.
    ///
    /// ВАЖНО: после первого появления лунки её массив здесь больше НИКОГДА
    /// не перезаписывается снимком целиком — apply(snapshot:) только
    /// обновляет `snapshot` (пар/дистанции/список клюшек) и досеивает
    /// лунки, которых ещё не было. Так локальные, ещё не подтверждённые
    /// телефоном удары (добавленные на часах) не теряются молча при каждом
    /// новом снимке.
    private(set) var shotsByHole: [Int: [String]] = [:]

    /// Последняя использованная клюшка (по всему раунду, не только текущей
    /// лунке) — дефолт для addShot(), когда пикер явно не трогали.
    private var lastUsedClub: String?

    /// Выбор пикера клюшек. Не сбрасывается автоматически после addShot() —
    /// повторные удары той же клюшкой (частый случай, напр. пары ударов
    /// подряд одной клюшкой) не требуют повторного выбора.
    var selectedClub: String?

    init(snapshot: WatchRoundSnapshot?) {
        self.snapshot = snapshot
        if let snapshot {
            holeNumber = Self.clampHole(snapshot.activeHoleNumber, totalHoles: snapshot.totalHoles)
            seedIfNeeded(from: snapshot)
        }
    }

    /// Применяет новый снимок с телефона. См. комментарий у shotsByHole —
    /// локальные удары уже виденных лунок сохраняются поверх, независимо от
    /// того, что пришло в снимке.
    func apply(snapshot: WatchRoundSnapshot) {
        self.snapshot = snapshot
        seedIfNeeded(from: snapshot)
    }

    var currentHole: WatchHole? {
        snapshot?.holes.first { $0.number == holeNumber }
    }

    var clubs: [String] {
        snapshot?.clubs ?? []
    }

    /// Клюшки ударов ТЕКУЩЕЙ лунки.
    var shots: [String] {
        shotsByHole[holeNumber] ?? []
    }

    /// Сколько ударов текущей лунки ещё не подтверждено телефоном (введено
    /// на часах, но сервер/снимок ещё не отразил это в myShots).
    var pendingCount: Int {
        max(0, shots.count - confirmedCount(forHole: holeNumber))
    }

    func addShot() {
        guard let club = selectedClub ?? lastUsedClub ?? clubs.first else { return }
        shotsByHole[holeNumber, default: []].append(club)
        lastUsedClub = club
    }

    func removeShot() {
        guard var holeShots = shotsByHole[holeNumber], !holeShots.isEmpty else { return }
        holeShots.removeLast()
        shotsByHole[holeNumber] = holeShots
    }

    func nextHole() {
        guard let snapshot else { return }
        holeNumber = Self.clampHole(holeNumber + 1, totalHoles: snapshot.totalHoles)
    }

    func previousHole() {
        guard let snapshot else { return }
        holeNumber = Self.clampHole(holeNumber - 1, totalHoles: snapshot.totalHoles)
    }

    // MARK: - Private

    private func confirmedCount(forHole hole: Int) -> Int {
        snapshot?.holes.first { $0.number == hole }?.myShots ?? 0
    }

    private func seedIfNeeded(from snapshot: WatchRoundSnapshot) {
        let placeholder = snapshot.clubs.first ?? "?"
        for hole in snapshot.holes where shotsByHole[hole.number] == nil {
            shotsByHole[hole.number] = Array(repeating: placeholder, count: max(0, hole.myShots))
        }
    }

    private static func clampHole(_ number: Int, totalHoles: Int) -> Int {
        guard totalHoles > 0 else { return 1 }
        return min(max(number, 1), totalHoles)
    }
}
