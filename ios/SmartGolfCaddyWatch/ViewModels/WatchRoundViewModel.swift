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
    /// перескакивает сюда за activeHoleNumber телефона В ПРЕДЕЛАХ ОДНОГО
    /// раунда: игрок может листать лунки на часах (посмотреть пар/
    /// дистанцию), не двигая прогресс на телефоне, и это не должно дёргать
    /// текущий экран из-под пальца. Стартовое значение — единственное место
    /// (наравне со сменой раунда, см. apply(snapshot:)), где
    /// activeHoleNumber снимка используется.
    ///
    /// Это правило НЕ действует при смене раунда (snapshot.roundId
    /// меняется) — тогда holeNumber пересчитывается заново из
    /// activeHoleNumber нового раунда, т.к. номер лунки прошлого раунда
    /// бессмысленен в контексте нового.
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
    ///
    /// ИСКЛЮЧЕНИЕ — смена раунда (snapshot.roundId != текущего): весь
    /// локальный прогресс раунда А бессмысленен (и ОПАСЕН) в контексте
    /// раунда Б — без сброса лунка N раунда Б унаследовала бы
    /// неподтверждённые удары лунки N раунда А (seedIfNeeded пропустил бы
    /// её как уже виденную), а lastUsedClub/selectedClub протекли бы из
    /// прошлого раунда. Поэтому при смене roundId стираем shotsByHole,
    /// lastUsedClub, selectedClub и заново выводим holeNumber из
    /// activeHoleNumber нового снимка — тем же путём, что в init — ПЕРЕД
    /// посевом.
    func apply(snapshot: WatchRoundSnapshot) {
        if self.snapshot?.roundId != snapshot.roundId {
            shotsByHole = [:]
            lastUsedClub = nil
            selectedClub = nil
            holeNumber = Self.clampHole(snapshot.activeHoleNumber, totalHoles: snapshot.totalHoles)
        }
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

    /// Удары указанной лунки, которые ДЕЙСТВИТЕЛЬНО были введены на часах и
    /// ещё не подтверждены телефоном — единственное безопасное для отправки
    /// (Task 4, WatchShotBatch) подмножество shotsByHole[hole]. Возвращает
    /// хвост массива ЗА пределами confirmedCount(forHole:) — префикс до
    /// этой границы состоит из плейсхолдеров, посеянных seedIfNeeded по
    /// чужим (введённым на телефоне) ударам, и НЕ должен уходить на сервер:
    /// recordShot пишет весь массив клюшек лунки целиком, поэтому отправка
    /// префикса затёрла бы настоящие клюшки заглушками "clubs.first"/"?".
    func unsyncedShots(forHole hole: Int) -> [String] {
        let holeShots = shotsByHole[hole] ?? []
        let confirmed = confirmedCount(forHole: hole)
        guard holeShots.count > confirmed else { return [] }
        return Array(holeShots[confirmed...])
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

    /// ВАЖНО: посеянный префикс — это ЗАГЛУШКИ (clubs.first/"?"), не
    /// реальные названия клюшек чужих (телефонных) ударов. Отправлять его
    /// на телефон НЕЛЬЗЯ — используй unsyncedShots(forHole:), который режет
    /// именно этот префикс.
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
