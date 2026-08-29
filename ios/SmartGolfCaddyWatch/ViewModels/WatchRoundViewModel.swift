// ios/SmartGolfCaddyWatch/ViewModels/WatchRoundViewModel.swift
// Чистая логика экрана лунки на часах. НИКАКИХ WatchConnectivity-вызовов —
// снимок подаётся снаружи (init/apply), отправка батчей — задача Task 4.
// import WatchConnectivity запрещён в этом файле (см. CLAUDE.md).
//
// МОДЕЛЬ (переписана целиком живым ревью Task 4 после пятого раунда
// правок одного и того же узла — Fix 2/7/9 латали границу
// "confirmedCount vs myShots vs локальный кэш", пока не выяснилось, что
// сама граница и есть корень проблемы). Больше НЕТ in-memory кэша
// "clubs по лункам" и НЕТ понятия confirmedCount. Вместо этого — две
// НЕПЕРЕСЕКАЮЩИЕСЯ ПО ПОСТРОЕНИЮ величины, каждая читается ЖИВЬЁМ из
// своего источника при каждом обращении:
//   - серверная часть — snapshot.holes[...].myShots;
//   - локальный хвост — shotQueue.pending(hole)?.clubs (durable,
//     единственный источник "что часы ввели, а телефон ещё не принял").
// Отображаемый счёт = их сумма. addShot() дописывает в durable-хвост
// БЕЗ каких-либо сравнений с myShots — никогда не no-op. removeShot()
// снимает последний элемент ТОЛЬКО из локального хвоста; если хвост
// пуст, удар уже на сервере — с часов его не снимаем.
//
// Поскольку ничего не кэшируется в памяти, "рехидратация после
// перезапуска часов" (Fix 7) больше не отдельная механика, которую можно
// забыть или сломать заново — каждое обращение к pendingClubs/shotCount
// читает durable-очередь напрямую, так что пересозданная после выгрузки
// VM автоматически видит актуальное состояние.
//
// ОСОЗНАННЫЙ КОМПРОМИСС: между моментом, когда телефон записал удар на
// сервер (myShots вырос), и моментом, когда квитанция срезала хвост в
// shotQueue.pending на часах, отображаемый счёт кратковременно завышен —
// удар посчитан и в myShots, и в ещё не срезанном хвосте. Это
// самоустраняющееся косметическое расхождение в узком окне (секунды на
// доставку quitanции), СТРОГО лучше прежнего поведения (молчаливая
// потеря удара). Ни потери, ни дубля НА СЕРВЕРЕ это не даёт: туда уходит
// сам durable-хвост, а от повторной записи защищает дедуп по
// WatchShotEntry.sequence (WatchBridge.applyBatch).
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
    private let shotQueue: WatchShotQueue

    /// Лунки, для которых пришла квитанция "сервер окончательно отклонил"
    /// (Fix 3, живое ревью Task 4) — UI показывает явную ошибку синхронизации
    /// вместо бесконечного "не синхронизировано". Сбрасывается для лунки
    /// при новой попытке (addShot/removeShot на ней) и целиком при смене
    /// раунда.
    private(set) var syncFailedHoles: Set<Int> = []
    private var syncFailedObserver: NSObjectProtocol?

    init(snapshot: WatchRoundSnapshot?, shotQueue: WatchShotQueue = .shared) {
        self.snapshot = snapshot
        self.shotQueue = shotQueue
        if let snapshot {
            holeNumber = Self.clampHole(snapshot.activeHoleNumber, totalHoles: snapshot.totalHoles)
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

    /// Применяет новый снимок с телефона. Никакого локального кэша клюшек
    /// здесь больше нет (см. заголовок файла) — обновить нужно только сам
    /// `snapshot`.
    ///
    /// ИСКЛЮЧЕНИЕ — смена раунда (snapshot.roundId != текущего):
    /// lastUsedClub/selectedClub/syncFailedHoles от раунда А бессмысленны
    /// (и потенциально вводят в заблуждение) в контексте раунда Б, поэтому
    /// сбрасываются; holeNumber пересчитывается заново из
    /// activeHoleNumber нового снимка — тем же путём, что в init.
    /// Срабатывает и когда self.snapshot == nil (VM создана как
    /// `WatchRoundViewModel(snapshot: nil)`), не только при смене
    /// roundId — VM не полагается на дисциплину вызывающей стороны
    /// (Fix 6, живое ревью Task 4).
    func apply(snapshot: WatchRoundSnapshot) {
        if self.snapshot?.roundId != snapshot.roundId {
            let oldRoundId = self.snapshot?.roundId
            lastUsedClub = nil
            selectedClub = nil
            syncFailedHoles = []
            if let oldRoundId {
                // Гигиена, не корректность — ключи sequence уже несут
                // roundId, поэтому записи старого раунда физически не
                // читаются для нового и без этой очистки. Пропускается,
                // когда oldRoundId нет (nil-старт — чистить нечего).
                shotQueue.clearSequences(roundId: oldRoundId)
            }
            holeNumber = Self.clampHole(snapshot.activeHoleNumber, totalHoles: snapshot.totalHoles)
        }
        self.snapshot = snapshot
    }

    // MARK: - Локализация (Task 5)

    /// Язык часов: из активного снимка (телефон кладёт туда резолвнутый
    /// LocaleManager-ом язык пользователя — профиль или язык устройства),
    /// пока снимка нет — язык самих часов. Часы не имеют экрана настроек и
    /// не ходят в Firestore, поэтому язык может прийти ТОЛЬКО с телефона;
    /// AppLocaleStore (Models/Localization, подключён ссылкой) даёт
    /// системный фолбэк тем же способом, что и на телефоне при первом
    /// запуске без профиля.
    var locale: AppLocale { snapshot?.locale ?? AppLocaleStore.systemDefault }

    /// Словарь для текущего языка часов — тот же общий Strings.ru/.en, что
    /// и на телефоне (см. Strings.resolved). Пересчитывается при каждом
    /// обращении (нет кэша) — новый снимок с другим языком подхватывается
    /// автоматически, вью реагируют на изменение `snapshot`.
    var strings: Strings { Strings.resolved(locale) }

    var currentHole: WatchHole? {
        snapshot?.holes.first { $0.number == holeNumber }
    }

    var clubs: [String] {
        snapshot?.clubs ?? []
    }

    /// Клюшки ударов ТЕКУЩЕЙ лунки, введённые на часах и ещё НЕ
    /// подтверждённые телефоном — единственное безопасное для отправки
    /// (WatchShotBatch) содержимое. Читается напрямую из durable-очереди
    /// при каждом обращении, без промежуточного in-memory кэша.
    var pendingClubs: [String] {
        unsyncedShots(forHole: holeNumber)
    }

    /// То же самое для произвольной (не обязательно текущей) лунки.
    func unsyncedShots(forHole hole: Int) -> [String] {
        guard let snapshot else { return [] }
        return shotQueue.pending.first { $0.roundId == snapshot.roundId && $0.holeNumber == hole }?.clubs ?? []
    }

    /// Отображаемый счёт ТЕКУЩЕЙ лунки = сервер (myShots) + локальный
    /// неподтверждённый хвост. См. заголовок файла про осознанный
    /// компромисс кратковременного завышения в узком окне.
    var shotCount: Int {
        (currentHole?.myShots ?? 0) + pendingClubs.count
    }

    /// Сколько ударов текущей лунки ещё не подтверждено телефоном — для
    /// индикатора "не синхронизировано: N". Ровно длина локального хвоста.
    var pendingCount: Int {
        pendingClubs.count
    }

    /// Дописывает клюшку в durable-хвост текущей лунки. НЕ сравнивается с
    /// myShots ни в каком виде — не может оказаться no-op'ом (в отличие от
    /// прежней версии, где рассинхрон confirmedCount/myShots иногда делал
    /// добавленный удар невидимым для очереди).
    func addShot() {
        guard let snapshot else { return }
        guard let club = selectedClub ?? lastUsedClub ?? clubs.first else { return }
        syncFailedHoles.remove(holeNumber)
        lastUsedClub = club
        shotQueue.enqueue(roundId: snapshot.roundId, holeNumber: holeNumber, clubs: pendingClubs + [club])
    }

    /// Снимает последний удар ТОЛЬКО из локального (ещё не подтверждённого)
    /// хвоста. Если хвост пуст — крайний удар лунки уже записан на сервере,
    /// и с часов его снять НЕЛЬЗЯ (нет канала "отменить принятый recordShot"
    /// в эту сторону): no-op. По построению закрывает стирание чужого/
    /// серверного удара — не нужна отдельная защита вида allowClear.
    func removeShot() {
        guard let snapshot else { return }
        var tail = pendingClubs
        guard !tail.isEmpty else { return }
        tail.removeLast()
        syncFailedHoles.remove(holeNumber)
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

    private static func clampHole(_ number: Int, totalHoles: Int) -> Int {
        guard totalHoles > 0 else { return 1 }
        return min(max(number, 1), totalHoles)
    }
}
