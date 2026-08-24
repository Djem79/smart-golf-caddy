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

    /// Durable-очередь ударов на отправку телефону (Task 4). Инжектируется
    /// для тестов (временный файл) — вью продолжают вызывать init без
    /// изменений, дефолт .shared. НЕ WatchConnectivity — только файловая
    /// очередь, реальная отправка (flush) — забота вью-слоя.
    ///
    /// ВАЖНО (Fix 2, живое ревью Task 4): confirmedCount(forHole:) НЕ может
    /// полагаться только на snapshot.myShots — снимок обновляется ТОЛЬКО
    /// когда HoleTrackerViewModel.sendWatchSnapshot() вызван, а это
    /// происходит лишь пока на ТЕЛЕФОНЕ открыт экран лунки. В основном
    /// сценарии игры с часов телефон лежит в кармане с закрытым экраном —
    /// снимок не обновляется вовсе, и без доп. источника unsyncedShots()
    /// после КАЖДОЙ квитанции переоценивала бы уже подтверждённые клюшки
    /// как неподтверждённые, дописывая их на телефоне ВТОРОЙ раз при
    /// следующем addShot(). Поэтому confirmedCount берёт max(snapshot.myShots,
    /// shotQueue.confirmedCount(...)) — последний продвигается СРАЗУ по
    /// приходу квитанции (WatchShotQueue.markConfirmed), не дожидаясь
    /// нового снимка.
    private let shotQueue: WatchShotQueue

    /// Лунки, для которых пришла квитанция "сервер окончательно отклонил"
    /// (Fix 3, живое ревью Task 4) — UI показывает явную ошибку синхронизации
    /// вместо бесконечного "не синхронизировано". Сбрасывается для лунки
    /// при новой попытке (addShot/removeShot на ней, см. syncQueue()) и
    /// целиком при смене раунда.
    private(set) var syncFailedHoles: Set<Int> = []
    private var syncFailedObserver: NSObjectProtocol?

    init(snapshot: WatchRoundSnapshot?, shotQueue: WatchShotQueue = .shared) {
        self.snapshot = snapshot
        self.shotQueue = shotQueue
        if let snapshot {
            holeNumber = Self.clampHole(snapshot.activeHoleNumber, totalHoles: snapshot.totalHoles)
            seedIfNeeded(from: snapshot)
        }
        syncFailedObserver = NotificationCenter.default.addObserver(
            forName: .watchShotSyncFailed, object: nil, queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleSyncFailed(notification)
            }
        }
    }

    @MainActor deinit {
        if let syncFailedObserver { NotificationCenter.default.removeObserver(syncFailedObserver) }
    }

    /// Индикатор для UI: сервер окончательно отклонил хотя бы одну попытку
    /// синхронизации текущей лунки.
    var currentHoleSyncFailed: Bool {
        syncFailedHoles.contains(holeNumber)
    }

    private func handleSyncFailed(_ notification: Notification) {
        guard let roundId = notification.userInfo?["roundId"] as? String,
              let hole = notification.userInfo?["holeNumber"] as? Int,
              roundId == snapshot?.roundId else { return }
        syncFailedHoles.insert(hole)
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
    /// ПРЕДУСЛОВИЕ: не полагается на то, вызывался ли уже init(snapshot:) с
    /// непустым снимком — ветка ниже срабатывает и когда self.snapshot ==
    /// nil (VM создана как `WatchRoundViewModel(snapshot: nil)`), не только
    /// при смене roundId (Fix 6, живое ревью Task 4: старая версия условия
    /// `if let oldRoundId = self.snapshot?.roundId, ...` требовала
    /// НЕПУСТОГО старого снимка и на nil-старте молча пропускала
    /// пересчёт holeNumber из activeHoleNumber нового снимка — в проде это
    /// сегодня недостижимо, `WatchRootView.syncViewModel` в этом случае
    /// создаёт VM заново, а не вызывает apply на nil-VM, но сама VM не
    /// должна полагаться на дисциплину вызывающей стороны).
    func apply(snapshot: WatchRoundSnapshot) {
        if self.snapshot?.roundId != snapshot.roundId {
            let oldRoundId = self.snapshot?.roundId
            shotsByHole = [:]
            lastUsedClub = nil
            selectedClub = nil
            syncFailedHoles = []
            if let oldRoundId {
                // Гигиена, не корректность (см. WatchShotQueue.clearConfirmedCounts/
                // clearSequences) — ключи confirmedCount/sequence уже несут
                // roundId, поэтому записи старого раунда физически не
                // читаются для нового и без этой очистки. Пропускается,
                // когда oldRoundId нет (nil-старт — чистить нечего).
                shotQueue.clearConfirmedCounts(roundId: oldRoundId)
                shotQueue.clearSequences(roundId: oldRoundId)
            }
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
    /// на часах, но сервер/снимок ещё не отразил это в myShots). См.
    /// комментарий у shotQueue про то, почему это НЕ прямое чтение очереди.
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
        // allowClear: false (Fix 7, живое ревью Task 4) — addShot() ТОЛЬКО
        // добавляет, никогда не должен привести к УДАЛЕНИЮ существующего
        // durable-хвоста как побочный эффект. См. syncQueue().
        syncQueue(allowClear: false)
    }

    func removeShot() {
        guard var holeShots = shotsByHole[holeNumber], !holeShots.isEmpty else { return }
        holeShots.removeLast()
        shotsByHole[holeNumber] = holeShots
        // allowClear: true — снятие хвоста ДО подтверждённого остатка
        // (пустой unsyncedShots) здесь легитимно: игрок сам убрал
        // непосредственно то, что было в очереди.
        syncQueue(allowClear: true)
    }

    /// Держит WatchShotQueue синхронной с реально введённым на часах хвостом
    /// текущей лунки — вызывается после КАЖДОГО addShot()/removeShot().
    /// unsyncedShots(forHole:) уже отфильтровывает плейсхолдеры seedIfNeeded
    /// (см. её комментарий) — поэтому в очередь никогда не попадают
    /// заглушки, только реально введённые на часах клюшки.
    ///
    /// `allowClear` (Fix 7, живое ревью Task 4): пустой unsyncedShots может
    /// означать ДВЕ разные вещи — (а) игрок сам убрал все неподтверждённые
    /// удары (removeShot — легитимно снять durable-хвост целиком) или
    /// (б) рассогласование, при котором confirmedCount(forHole:) обогнал
    /// локальный shotsByHole[hole] по причине, не связанной с ЭТИМ
    /// действием игрока (например, свежий снимок телефона сообщил больше
    /// подтверждённых ударов, чем часы успели узнать) — тогда пустой
    /// `enqueue(clubs: [])` молча стёр бы РЕАЛЬНЫЙ durable-хвост, ещё не
    /// подтверждённый телефоном. addShot() зовёт с `allowClear: false` —
    /// он только ДОБАВЛЯЕТ, значит опустошение хвоста здесь не может быть
    /// намерением игрока; если пусто — просто не трогаем очередь.
    private func syncQueue(allowClear: Bool) {
        guard let snapshot else { return }
        // Новая локальная попытка (добавили/убрали удар) на лунке,
        // помеченной как "не удалось синхронизировать" — даём чистый
        // старт, а не оставляем зависший индикатор ошибки поверх нового
        // хвоста, который ещё даже не отправлялся.
        syncFailedHoles.remove(holeNumber)
        let tail = unsyncedShots(forHole: holeNumber)
        guard !tail.isEmpty || allowClear else { return }
        shotQueue.enqueue(roundId: snapshot.roundId, holeNumber: holeNumber, clubs: tail)
    }

    func nextHole() {
        guard let snapshot else { return }
        holeNumber = Self.clampHole(holeNumber + 1, totalHoles: snapshot.totalHoles)
    }

    func previousHole() {
        guard let snapshot else { return }
        holeNumber = Self.clampHole(holeNumber - 1, totalHoles: snapshot.totalHoles)
    }

    // MARK: - Дистанция до грина (Task 5)

    /// Текущий GPS-фикс часов — подаётся СНАРУЖИ (WatchHoleView читает
    /// WatchLocationService.lastFix и толкает его сюда через onChange).
    /// import CoreLocation запрещён в этом файле (см. CLAUDE.md) — VM
    /// работает только с Foundation-типом GeoFix (Models/Geo.swift), не
    /// зная, как именно фикс был получен. nil = фикс ещё не пришёл.
    var currentFix: GeoFix?

    /// Дистанция до грина ТЕКУЩЕЙ лунки, метры. Гейты — ТЕ ЖЕ, что у
    /// дальномера телефона: `GeoGates` в Models/Geo.swift, единое место
    /// для обеих платформ (Models/ подключён ссылкой в watch target, в
    /// отличие от Services/ — см. project.yml sources).
    ///
    /// nil = недостоверно («—» в UI, а НЕ 0 и НЕ устаревшее значение) — при
    /// негодном фиксе, отсутствии метки грина для лунки в снимке ИЛИ
    /// дистанции за пределами разумного (см. GeoGates.clampGreenDistance —
    /// тот же клэмп, что и в HoleTrackerViewModel.applyGreenMarks на
    /// телефоне). Вычисляется заново при каждом обращении (не кэшируется) —
    /// так смена лунки или новый фикс подхватываются автоматически.
    var greenDistanceMeters: Int? {
        guard let fix = currentFix, GeoGates.isUsable(fix) else { return nil }
        guard let green = snapshot?.greens[holeNumber] else { return nil }
        let meters = Greens.distanceMeters(from: fix, to: green)
        return GeoGates.clampGreenDistance(meters)
    }

    // MARK: - Private

    /// max(snapshot.myShots, shotQueue.confirmedCount) — см. комментарий у
    /// `shotQueue`/Fix 2 живого ревью Task 4: снимок отстаёт, пока на
    /// телефоне закрыт экран лунки, квитанция — нет.
    private func confirmedCount(forHole hole: Int) -> Int {
        let fromSnapshot = snapshot?.holes.first { $0.number == hole }?.myShots ?? 0
        guard let roundId = snapshot?.roundId else { return fromSnapshot }
        return max(fromSnapshot, shotQueue.confirmedCount(roundId: roundId, holeNumber: hole))
    }

    /// ВАЖНО: посеянный префикс — это ЗАГЛУШКИ (clubs.first/"?"), не
    /// реальные названия клюшек чужих (телефонных) ударов. Отправлять его
    /// на телефон НЕЛЬЗЯ — используй unsyncedShots(forHole:), который режет
    /// именно этот префикс.
    ///
    /// РОВНО ОДИН РАЗ на лунку (то же условие, что и для плейсхолдеров)
    /// поднимает durable-базу shotQueue.confirmedCount до hole.myShots —
    /// без этого markConfirmed прибавлял бы квитанции к нулю, а не к уже
    /// подтверждённому сервером количеству (Fix 2, живое ревью Task 4, см.
    /// WatchShotQueue.seedConfirmedCountIfHigher).
    ///
    /// Fix 7 (живое ревью Task 4) — ВОССТАНОВЛЕНИЕ после выгрузки процесса
    /// часов: `shotsByHole` живёт ТОЛЬКО в памяти, watchOS штатно убивает
    /// приложение между запусками. Без рехидратации первый посев лунки
    /// после перезапуска брал только `hole.myShots` (снимок телефона) —
    /// РЕАЛЬНЫЙ, ещё не подтверждённый удар, уже лежащий на диске в
    /// `shotQueue` (батч мог уйти до выгрузки), терялся из вида: локальный
    /// счёт занижался, а следующий unsyncedShots() у уже "полного" по
    /// confirmedCount состояния возвращал бы [] — и `enqueue(clubs: [])`
    /// стёр бы durable-хвост вместо того, чтобы поставить в очередь НОВЫЙ
    /// удар игрока (см. syncQueue/allowClear).
    ///
    /// Fix 9 (живое ревью, поверх Fix 7) — ОБЩИЙ РАЗМЕР лунки, а не сумма
    /// слагаемых вслепую. `confirmedCount` и `pendingClubs.count`
    /// дизъюнктны МЕЖДУ СОБОЙ (markConfirmed срезает подтверждённый
    /// префикс из pending) — но `hole.myShots` дизъюнктен с
    /// `confirmedCount + pendingClubs.count` НЕ гарантированно: это два
    /// НЕЗАВИСИМЫХ канала (снимок едет через updateApplicationContext,
    /// квитанция — через transferUserInfo) и могут описывать ОДНО И ТО ЖЕ
    /// событие, обогнав друг друга в любую сторону. Первая версия Fix 7
    /// складывала `max(myShots, confirmedCount)` заглушками ПЛЮС
    /// `pending.clubs` — если снимок уже обогнал квитанцию (myShots уже
    /// учёл удар, который confirmedCount ещё не видел, а pending его ещё
    /// не срезал), один и тот же удар засчитывался ДВАЖДЫ. Правильная
    /// формула берёт максимум по ОБЩЕМУ РАЗМЕРУ лунки:
    /// `total = max(hole.myShots, confirmedCount + pendingClubs.count)`,
    /// число заглушек — `total - pendingClubs.count`, хвост — сам
    /// `pendingClubs` (он всегда реальный, не выдумывается).
    private func seedIfNeeded(from snapshot: WatchRoundSnapshot) {
        let placeholder = snapshot.clubs.first ?? "?"
        let holesToSeed = snapshot.holes.filter { shotsByHole[$0.number] == nil }
        guard !holesToSeed.isEmpty else { return }

        let pendingByHole = Dictionary(
            uniqueKeysWithValues: shotQueue.pending
                .filter { $0.roundId == snapshot.roundId }
                .map { ($0.holeNumber, $0) }
        )

        for hole in holesToSeed {
            let confirmedCount = shotQueue.confirmedCount(roundId: snapshot.roundId, holeNumber: hole.number)
            let pendingClubs = pendingByHole[hole.number]?.clubs ?? []
            let total = max(hole.myShots, confirmedCount + pendingClubs.count)
            let placeholderCount = max(0, total - pendingClubs.count)
            shotsByHole[hole.number] = Array(repeating: placeholder, count: placeholderCount) + pendingClubs
            shotQueue.seedConfirmedCountIfHigher(roundId: snapshot.roundId, holeNumber: hole.number, count: hole.myShots)
        }
    }

    private static func clampHole(_ number: Int, totalHoles: Int) -> Int {
        guard totalHoles > 0 else { return 1 }
        return min(max(number, 1), totalHoles)
    }
}
