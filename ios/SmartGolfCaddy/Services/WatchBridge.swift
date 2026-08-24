// ios/SmartGolfCaddy/Services/WatchBridge.swift
// Мост iPhone → Apple Watch поверх WatchConnectivity. import WatchConnectivity
// разрешён ТОЛЬКО в этом файле и в SmartGolfCaddyWatch/Services/PhoneBridge.swift
// (см. CLAUDE.md). Снимок раунда шлём через updateApplicationContext —
// последнее состояние всегда актуально, старые снимки перезаписываются без
// накопления очереди. Удары от часов приходят через didReceiveUserInfo —
// это гарантированная доставка со стороны часов, переживающая недоступность
// связи.
//
// КРИТИЧЕСКИЙ ИНВАРИАНТ (Task 4): recordShot пишет ВЕСЬ массив клюшек лунки
// целиком (идемпотентно по замыслу) — значит отправка неполного массива
// затирает то, что уже знает сервер. Часы шлют ТОЛЬКО unsyncedShots — хвост
// реально введённых на часах клюшек, БЕЗ префикса (выбран вариант (а) из
// брифа задачи, не (б) "часы шлют полный массив, только когда он весь
// реален" — часы физически не знают имена чужих/телефонных клюшек, только
// заглушки, поэтому "весь реальный массив" на часах в принципе недостижим
// для лунки, начатой на телефоне). Поэтому телефон здесь ДОПИСЫВАЕТ хвост
// к уже известным клюшкам лунки — см. applyBatch/baseState ниже.
import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// Вызывается на main при получении пакета ударов от часов — ДО того,
    /// как батч применяется к ShotQueue (хук для UI/диагностики, само
    /// применение WatchBridge делает самостоятельно, см. applyBatch).
    var onShotBatch: ((WatchShotBatch) -> Void)?

    // MARK: - DI (живое ревью Task 4, Fix 4): applyBatch пишет на сервер и
    // содержит оба CRITICAL-фикса живого ревью (Fix 1/Fix 3) — должен быть
    // тестируемым без реального Firebase/WatchConnectivity. Дефолты бьют в
    // реальные сервисы; тесты подставляют fakes. Та же идея, что у
    // ShotRangefinder.init(storeURL:fixProvider:) — конкретный класс с
    // инжектируемыми зависимостями, а не protocol-абстракция.
    private let currentUserIdProvider: () async -> String?
    private let roundProvider: (String) async throws -> Round?
    private let pendingShotProvider: (String, Int, String) -> PendingShot?
    private let shotRecorder: (String, Int, String, [String], [Int]) async -> RecordOutcome
    private let receiptSender: (WatchShotReceipt) -> Void
    /// Fix 5+8 (живое ревью Task 4): последний применённый sequence на
    /// слот round:holeIndex:uid:installId — см. WatchBatchSequenceLedger.
    /// Заменяет suffix-эвристику по содержимому клюшек (первая версия
    /// Fix 4), которая молча теряла повторный удар той же клюшкой (второй
    /// патт подряд ошибочно считался "уже применённым батчем").
    /// installId (Fix 8) — идентификатор УСТАНОВКИ приложения часов,
    /// приславшей батч: без него переустановка часов (sequence-счётчик
    /// на них обнуляется вместе с файлом) коллизировала бы с sequence
    /// прежней установки в этом журнале.
    private let lastAppliedSequenceProvider: (String, Int, String, String) -> Int?
    private let sequenceRecorder: (String, Int, String, String, Int) -> Void

    init(
        currentUserIdProvider: @escaping () async -> String? = { await AuthService.currentUserId },
        roundProvider: @escaping (String) async throws -> Round? = { try await RoundsService.getRound(roundId: $0) },
        pendingShotProvider: @escaping (String, Int, String) -> PendingShot? = { roundId, holeIndex, uid in
            ShotQueue.shared.pendingShot(roundId: roundId, holeIndex: holeIndex, targetUid: uid)
        },
        shotRecorder: @escaping (String, Int, String, [String], [Int]) async -> RecordOutcome = { roundId, holeIndex, uid, clubs, distances in
            await ShotQueue.shared.recordShotQueued(roundId: roundId, holeIndex: holeIndex, targetUid: uid, clubs: clubs, distances: distances)
        },
        receiptSender: @escaping (WatchShotReceipt) -> Void = { WatchBridge.transferReceipt($0) },
        lastAppliedSequenceProvider: @escaping (String, Int, String, String) -> Int? = { roundId, holeIndex, uid, installId in
            WatchBatchSequenceLedger.shared.lastApplied(roundId: roundId, holeIndex: holeIndex, uid: uid, installId: installId)
        },
        sequenceRecorder: @escaping (String, Int, String, String, Int) -> Void = { roundId, holeIndex, uid, installId, sequence in
            WatchBatchSequenceLedger.shared.recordApplied(roundId: roundId, holeIndex: holeIndex, uid: uid, installId: installId, sequence: sequence)
        }
    ) {
        self.currentUserIdProvider = currentUserIdProvider
        self.roundProvider = roundProvider
        self.pendingShotProvider = pendingShotProvider
        self.shotRecorder = shotRecorder
        self.receiptSender = receiptSender
        self.lastAppliedSequenceProvider = lastAppliedSequenceProvider
        self.sequenceRecorder = sequenceRecorder
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(snapshot: WatchRoundSnapshot) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        do {
            try session.updateApplicationContext(snapshot.payload)
        } catch {
            // Не бросаем дальше — отсутствие связи с часами не должно ронять
            // экран лунки на телефоне.
            #if DEBUG
            print("WatchBridge: не удалось отправить снимок раунда: \(error)")
            #endif
        }
    }

    /// Квитанция о приёме батча — часы срезают ею свою локальную очередь
    /// (WatchShotQueue.markConfirmed). transferUserInfo — гарантированная
    /// доставка (переживает недоступность часов), тот же канал, что и
    /// исходящий батч, только в обратную сторону.
    func send(receipt: WatchShotReceipt) {
        Self.transferReceipt(receipt)
    }

    /// Свободная функция (не instance method) — используется и `send(receipt:)`,
    /// и дефолтом `receiptSender` в init: дефолтное значение параметра не
    /// может захватить `self` (объект ещё не существует в момент вычисления
    /// дефолта), поэтому реализация вынесена сюда.
    private static func transferReceipt(_ receipt: WatchShotReceipt) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(receipt.payload)
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if DEBUG
        if let error {
            print("WatchBridge: ошибка активации сессии: \(error)")
        }
        #endif
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        // Требуется протоколом на iOS (переход в неактивное состояние,
        // например при выборе других часов) — реактивации не требует.
    }

    func sessionDidDeactivate(_ session: WCSession) {
        // Пользователь сменил часы — на iOS сессию нужно реактивировать
        // вручную для новой пары часов.
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let batch = WatchShotBatch(payload: userInfo) else {
            #if DEBUG
            print("WatchBridge: не удалось разобрать пакет ударов от часов: \(userInfo)")
            #endif
            return
        }
        DispatchQueue.main.async { [weak self] in
            self?.onShotBatch?(batch)
        }
        Task { [weak self] in
            await self?.applyBatch(batch)
        }
    }

    // MARK: - Применение батча ударов с часов

    /// Дописывает каждую запись батча к уже известным телефону клюшкам
    /// лунки и кладёт результат в ShotQueue (свой uid — замер удара
    /// остаётся ТОЛЬКО на телефоне, distances не шлём с часов). Раунд
    /// читается ОДИН раз на весь батч (в WatchShotBatch один roundId на все
    /// entries) — не по одному fetch на лунку.
    ///
    /// Если раунд прочитать не удалось — НЕ пишем вообще: без знания
    /// текущего префикса клюшек лунки писать нельзя (см. критический
    /// инвариант вверху файла). Квитанция в этом случае не уходит — часы
    /// повторят отправку на следующем flush(), потери данных нет.
    ///
    /// Не `private` — тестовый seam (Fix 4, живое ревью): SmartGolfCaddyTests
    /// вызывает это напрямую на инстансе с инжектированными providers.
    func applyBatch(_ batch: WatchShotBatch) async {
        guard let uid = await currentUserIdProvider(), !uid.isEmpty else {
            #if DEBUG
            print("WatchBridge: нет авторизованного пользователя — батч ударов от часов отброшен")
            #endif
            return
        }
        guard let round = try? await roundProvider(batch.roundId) else {
            #if DEBUG
            print("WatchBridge: не удалось прочитать раунд \(batch.roundId) для мерджа батча с часов")
            #endif
            return
        }

        var receiptEntries: [WatchShotReceiptEntry] = []
        for entry in batch.entries {
            let holeIndex = entry.holeNumber - 1
            guard round.holes.indices.contains(holeIndex) else { continue }

            // Fix 5 (живое ревью Task 4): идемпотентность повторной доставки
            // ЧЕРЕЗ sequence, НЕ через совпадение содержимого клюшек — суффиксная
            // эвристика (первая версия Fix 4) путала "этот батч уже применён" с
            // "игрок ударил той же клюшкой ещё раз" (второй патт подряд, тот же
            // клуб — база УЖЕ заканчивалась на него до всякого повтора) и молча
            // теряла реальный новый удар. sequence — детерминированный номер
            // конкретной "поимки" хвоста на часах (WatchShotQueue.enqueue),
            // однозначно отличающий повтор от новой отправки.
            let lastApplied = lastAppliedSequenceProvider(batch.roundId, holeIndex, uid, entry.installId) ?? 0
            guard entry.sequence > lastApplied else {
                // Уже применено раньше (повторная доставка того же sequence —
                // throttle-ретрай на часах, гонка с запоздавшей оригинальной
                // отправкой). НЕ применяем повторно (иначе дубль), но всё
                // равно подтверждаем — иначе слот на часах зависнет навсегда.
                receiptEntries.append(WatchShotReceiptEntry(holeNumber: entry.holeNumber, acceptedCount: entry.clubs.count, accepted: true))
                continue
            }

            let base = baseState(round: round, holeIndex: holeIndex, uid: uid)
            let fullClubs = base.clubs + entry.clubs
            let fullDistances = base.distances + Array(repeating: 0, count: entry.clubs.count)

            let outcome = await shotRecorder(batch.roundId, holeIndex, uid, fullClubs, fullDistances)
            switch outcome {
            case .synced, .queued:
                // Обе ветки означают, что удар ДУРАБЕЛЬНО осел на
                // телефоне (ShotQueue пишет на диск ДО попытки сети) —
                // фиксируем sequence как применённый и подтверждаем часам.
                sequenceRecorder(batch.roundId, holeIndex, uid, entry.installId, entry.sequence)
                receiptEntries.append(WatchShotReceiptEntry(holeNumber: entry.holeNumber, acceptedCount: entry.clubs.count, accepted: true))
            case .rejected:
                // Сервер ОКОНЧАТЕЛЬНО отверг запись (permanent error) —
                // повтор с тем же payload даст ту же ошибку. sequence НЕ
                // фиксируем (запись реально не удалась), но подтверждаем
                // (accepted: false) — часы снимут слот и покажут "не удалось
                // синхронизировать" вместо вечного "не синхронизировано"
                // (Fix 3, живое ревью).
                #if DEBUG
                print("WatchBridge: recordShot отклонён сервером для лунки \(entry.holeNumber)")
                #endif
                receiptEntries.append(WatchShotReceiptEntry(holeNumber: entry.holeNumber, acceptedCount: entry.clubs.count, accepted: false))
            }
        }
        guard !receiptEntries.isEmpty else { return }
        receiptSender(WatchShotReceipt(roundId: batch.roundId, entries: receiptEntries))
    }

    /// Базовое (уже известное телефону) состояние клюшек лунки для мерджа
    /// с часовым хвостом (Fix 1, живое ревью Task 4). Приоритет:
    /// `pendingShotProvider` (= ShotQueue.pendingShot) ПЕРВЫМ — если для
    /// этого слота УЖЕ есть локальная запись, она равна "сервер + всё, что
    /// телефон САМ записал офлайн, возможно ещё не долетевшее до
    /// Firestore" — более полное состояние, чем `round.holes[...].shots`,
    /// прочитанные через `roundProvider` (который, даже с source: .server,
    /// не увидит СОБСТВЕННУЮ ещё не отправленную офлайн-запись телефона —
    /// recordShot идёт через Cloud Function, а не прямой клиентский write,
    /// оптимистичного обновления кэша для него нет). Без этого приоритета
    /// офлайн-удар, записанный на телефоне, был бы затёрт батчем с часов.
    /// Только если pending-записи для слота нет — используем серверный
    /// `resolvedClubs`.
    private func baseState(round: Round, holeIndex: Int, uid: String) -> (clubs: [String], distances: [Int]) {
        if let pending = pendingShotProvider(round.id, holeIndex, uid) {
            let clubs = pending.clubs
            var distances = pending.distances ?? []
            if distances.count < clubs.count {
                distances += Array(repeating: 0, count: clubs.count - distances.count)
            } else if distances.count > clubs.count {
                distances = Array(distances.prefix(clubs.count))
            }
            return (clubs, distances)
        }
        let shots = round.holes[holeIndex].shots[uid]
        return (shots?.resolvedClubs ?? [], shots?.resolvedDistances ?? [])
    }
}
