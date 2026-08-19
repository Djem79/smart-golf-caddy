// ios/SmartGolfCaddy/ViewModels/HoleTrackerViewModel.swift
// Порт HoleTracker.tsx: оптимистичный оверлей поверх Firestore + офлайн-
// очереди. Слот "\(holeIndex):\(activeUserId)" не даёт оверлею одной лунки/
// игрока протечь в другую; awaitingKey гасит оверлей, как только сервер
// отэхоил ровно те же клюшки. activeUserId — игрок, за которого хост
// ведёт счёт (по умолчанию сам userId).
import Foundation
import Observation

@Observable
@MainActor
final class HoleTrackerViewModel {

    struct Optimistic: Equatable {
        var slot: String
        var clubs: [String]
        var distances: [Int] = []
        var awaitingKey: String
    }

    let roundId: String
    let holeIndex: Int
    let userId: String

    /// Игрок, за которого сейчас ведётся счёт. По умолчанию — сам userId;
    /// хост может переключить на любого участника (setActiveUser). Все
    /// операции записи (слот очереди, метки дальномера) следуют за этим
    /// значением, а не за userId — иначе переключение мид-сейв протекает
    /// в чужой слот (находка финального ревью Фазы 2в).
    private(set) var activeUserId: String

    var round: Round?
    var loadError: String?
    var saveError: String?
    var saving = false
    var finishing = false
    var hasQueuedShots = false
    var optimistic: Optimistic?

    /// Усреднённые метки грина по всем игрокам поля (сырые, до пересчёта
    /// дистанции) — хранятся, чтобы applyGreenMarks можно было перевызвать
    /// с новым фиксом без повторной подписки.
    private var greenMarks: [GreenMarkSet] = []
    /// Дистанция до грина в метрах. nil = нет меток на эту лунку или фикс
    /// недостаточно точный/свежий (тот же гейт, что и у дальномера ударов).
    private(set) var greenDistanceMeters: Int?
    /// Индикатор для UI: можно ли поставить метку грина прямо сейчас.
    /// Отметить грин можно, когда есть годный фикс И известно поле раунда
    /// (без courseKey markGreen() молча вернёт false — без этого условия
    /// кнопка выглядела бы активной, но не срабатывала до первого снапшота
    /// раунда).
    var canMarkGreen: Bool {
        courseKey != nil && ShotRangefinder.isUsable(GeolocationService.shared.lastFix)
    }

    /// Ключ поля (Greens.courseKey) — известен только после первого снапшота
    /// раунда (courseId/courseName приходят из Round). До этого подписки на
    /// метки нет.
    private var courseKey: String?
    private var unsubscribeGreens: (() -> Void)?

    private var unsubscribe: (() -> Void)?
    private var queueObserver: NSObjectProtocol?
    // Дальномер инжектируется для тестов; вью продолжают вызывать init без
    // изменений — дефолт .shared.
    private let rangefinder: ShotRangefinder

    init(roundId: String, holeIndex: Int, userId: String, rangefinder: ShotRangefinder = .shared) {
        self.roundId = roundId
        self.holeIndex = holeIndex
        self.userId = userId
        self.activeUserId = userId
        self.rangefinder = rangefinder
    }

    var slotKey: String { "\(holeIndex):\(activeUserId)" }
    var hole: HoleConfig? {
        guard let round, round.holes.indices.contains(holeIndex) else { return nil }
        return round.holes[holeIndex]
    }
    var isHost: Bool { round?.hostId == userId }
    /// Разрешение вести счёт за других — только хост (сервер это enforce'ит,
    /// здесь дублируем для UI-гейтинга переключателя).
    var canScoreForOthers: Bool { round?.hostId == userId }
    /// GPS-замер достоверен только для своего слота: координаты устройства
    /// принадлежат userId, а не activeUserId, если хост ведёт счёт за другого.
    var measuresDistances: Bool { activeUserId == userId }

    /// Переключить активного игрока (только хост должен вызывать это для
    /// чужого uid — гейт на уровне UI, сервер дополнительно enforce'ит).
    /// Сбрасывает optimistic-оверлей — он слот-тегирован под предыдущего
    /// игрока и не должен протекать в новый слот. Повторный тап по уже
    /// активному игроку — no-op: иначе сброс optimistic посреди
    /// in-flight save откатил бы счётчик назад (мигание, находка Фазы 2а).
    func setActiveUser(_ uid: String) {
        guard uid != activeUserId else { return }
        activeUserId = uid
        optimistic = nil
    }

    /// Индикатор для UI: достаточно ли точен текущий GPS-фикс для замера.
    /// Вычисляемое свойство — не тикает по таймеру, обновится вместе со
    /// следующей перерисовкой SwiftUI на изменение состояния VM.
    var gpsReady: Bool { ShotRangefinder.isUsable(GeolocationService.shared.lastFix) }

    func start() {
        guard unsubscribe == nil else { return }
        GeolocationService.shared.startTracking()
        refreshQueueBadge()
        queueObserver = NotificationCenter.default.addObserver(
            forName: .shotQueueDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshQueueBadge() }
        }
        unsubscribe = RoundsService.subscribeToRound(
            roundId: roundId,
            onChange: { [weak self] round in
                guard let self else { return }
                self.round = round
                // Ключ поля известен только из раунда — поднимаем подписку на
                // метки при первом снапшоте (courseKey ещё не установлен).
                if self.courseKey == nil {
                    self.startGreens(courseKey: Greens.courseKey(courseId: round.courseId, courseName: round.courseName))
                }
                self.applyGreenMarks(self.greenMarks, fix: GeolocationService.shared.lastFix)
            },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить раунд. Проверьте связь."
            }
        )
    }

    private func startGreens(courseKey: String) {
        self.courseKey = courseKey
        unsubscribeGreens = GreensService.subscribeToMarks(
            courseKey: courseKey,
            onChange: { [weak self] sets in
                self?.applyGreenMarks(sets, fix: GeolocationService.shared.lastFix)
            },
            onError: { [weak self] _ in
                self?.loadError = "Не удалось загрузить метки грина."
            }
        )
    }

    /// Пересчёт дистанции до грина: чистая функция, тестируется напрямую
    /// без Firebase/CoreLocation. `holes` в метках индексируются с 1 (как в
    /// вебе), поэтому текущая лунка — `holeIndex + 1`. Гейт достоверности
    /// фикса переиспользует ShotRangefinder.isUsable — та же логика, что и
    /// для замера ударов, не дублируем.
    func applyGreenMarks(_ sets: [GreenMarkSet], fix: GeoFix?) {
        greenMarks = sets
        guard ShotRangefinder.isUsable(fix),
              let fix,
              let average = Greens.average(sets, hole: holeIndex + 1) else {
            greenDistanceMeters = nil
            return
        }
        greenDistanceMeters = Greens.distanceMeters(from: fix, to: average)
    }

    /// Поставить метку грина текущей лункой по текущему GPS-фиксу. Метка —
    /// это позиция ЭТОГО устройства, поэтому пишем под userId, а не
    /// activeUserId (аналогично measuresDistances — координаты устройства
    /// не принадлежат тому, за кого хост ведёт счёт).
    @discardableResult
    func markGreen() async -> Bool {
        guard let fix = GeolocationService.shared.lastFix, ShotRangefinder.isUsable(fix) else { return false }
        guard let courseKey else {
            saveError = "Раунд ещё загружается — попробуйте через секунду."
            return false
        }
        do {
            try await GreensService.saveMark(
                courseKey: courseKey, userId: userId, hole: holeIndex + 1, lat: fix.lat, lng: fix.lng
            )
            return true
        } catch {
            saveError = "Не удалось сохранить метку грина."
            return false
        }
    }

    /// Дерив отображаемой серии (порт myClubs из HoleTracker.tsx):
    /// optimistic пока «впереди» сервера → pending из очереди → server.
    func displayedClubs(serverClubs: [String], pendingClubs: [String]?) -> [String] {
        if let optimistic, optimistic.slot == slotKey,
           serverClubs.joined(separator: "|") != optimistic.awaitingKey {
            return optimistic.clubs
        }
        return pendingClubs ?? serverClubs
    }

    var currentClubs: [String] {
        let server = hole?.shots[activeUserId]?.resolvedClubs ?? []
        let pending = ShotQueue.shared.pendingShot(
            roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId
        )?.clubs
        return displayedClubs(serverClubs: server, pendingClubs: pending)
    }

    /// Дерив отображаемых дистанций — зеркалит displayedClubs: optimistic
    /// пока «впереди» сервера → pending из очереди → server.
    func displayedDistances(serverDistances: [Int], pendingDistances: [Int]?,
                             serverClubs: [String], pendingClubs: [String]?) -> [Int] {
        if let optimistic, optimistic.slot == slotKey,
           serverClubs.joined(separator: "|") != optimistic.awaitingKey {
            return optimistic.distances
        }
        return pendingDistances ?? serverDistances
    }

    var currentDistances: [Int] {
        let pending = ShotQueue.shared.pendingShot(
            roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId
        )
        return displayedDistances(
            serverDistances: hole?.shots[activeUserId]?.resolvedDistances ?? [],
            pendingDistances: pending?.distances,
            serverClubs: hole?.shots[activeUserId]?.resolvedClubs ?? [],
            pendingClubs: pending?.clubs
        )
    }

    /// Возвращает true при .synced/.queued (веб ставит lastClubUsed только на
    /// успешной мутации), false при .rejected (rollback-ветка).
    @discardableResult
    func save(_ clubs: [String]) async -> Bool {
        saving = true
        saveError = nil
        defer { saving = false }
        // Лёгкий пересчёт дистанции до грина на актуальном фиксе — полноценный
        // тик раз в секунду в беклоге (MVP: пересчёт на каждый save() и на
        // снапшоте раунда достаточен). Безусловно — не зависит от исхода
        // записи удара ниже.
        applyGreenMarks(greenMarks, fix: GeolocationService.shared.lastFix)

        let previous = currentClubs
        let next = clubs
        var distances = currentDistances

        if next.count > previous.count {
            let newIndex = next.count - 1
            // GPS-замер достоверен только для своего слота: координаты
            // устройства принадлежат userId, а не activeUserId, когда хост
            // ведёт счёт за другого — для чужого слота замер пропускаем
            // целиком (дистанция остаётся 0), иначе позиция хоста
            // приписалась бы товарищу.
            if measuresDistances {
                // Замер достоверен, только если метка принадлежит непосредственно
                // предыдущему удару: при пропущенной метке (слабый GPS) дистанция
                // покрыла бы несколько ударов сразу — такой замер отбрасываем.
                if let measured = rangefinder.measure(roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId),
                   measured.previousIndex == previous.count - 1,
                   measured.meters > 0,
                   distances.indices.contains(measured.previousIndex) {
                    distances[measured.previousIndex] = measured.meters
                }
                rangefinder.markShot(roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId, shotIndex: newIndex)
            }
        } else if next.count < previous.count {
            distances = Array(distances.prefix(next.count))
            // Точку замера переносим на последний оставшийся удар — иначе
            // следующий замер посчитал бы дистанцию от удалённого удара.
            if measuresDistances, next.count > 0 {
                rangefinder.markShot(roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId, shotIndex: next.count - 1)
            }
        }

        // Инвариант: длина distances == длине clubs — паддинг нулями/обрезка.
        if distances.count < next.count {
            distances += Array(repeating: 0, count: next.count - distances.count)
        } else if distances.count > next.count {
            distances = Array(distances.prefix(next.count))
        }

        optimistic = Optimistic(slot: slotKey, clubs: next, distances: distances,
                                awaitingKey: next.joined(separator: "|"))
        let outcome = await ShotQueue.shared.recordShotQueued(
            roundId: roundId, holeIndex: holeIndex, targetUid: activeUserId, clubs: next, distances: distances
        )
        if case .rejected = outcome {
            saveError = "Не удалось сохранить удар."
            if optimistic?.slot == slotKey { optimistic = nil }  // rollback слота
            refreshQueueBadge()
            return false
        }
        refreshQueueBadge()
        return true
    }

    func finish() async -> Bool {
        guard !finishing else { return false }
        finishing = true
        saveError = nil
        defer { finishing = false }
        do {
            try await RoundsService.finishRound(roundId: roundId)
            return true
        } catch {
            saveError = "Не удалось завершить раунд. Попробуйте ещё раз."
            return false
        }
    }

    func saveHoleConfig(par: Int?, distanceMeters: Int?) async -> Bool {
        do {
            try await RoundsService.updateHoleConfig(
                roundId: roundId, holeIndex: holeIndex,
                par: par, distanceMeters: distanceMeters
            )
            return true
        } catch {
            saveError = "Не удалось сохранить параметры лунки."
            return false
        }
    }

    private func refreshQueueBadge() {
        hasQueuedShots = ShotQueue.shared.pendingCount(roundId: roundId) > 0
    }

    @MainActor deinit {
        unsubscribe?()
        unsubscribeGreens?()
        if let queueObserver { NotificationCenter.default.removeObserver(queueObserver) }
        GeolocationService.shared.stopTracking()
    }
}
