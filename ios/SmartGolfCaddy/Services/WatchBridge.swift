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
// к уже известным клюшкам лунки (getHoleClubs-эквивалент — resolvedClubs),
// прочитанным СВЕЖИМ разовым запросом (RoundsService.getRound) — не из
// потенциально устаревшего кэша, иначе можно дописать поверх уже
// дописанного или наоборот потерять параллельно записанные на телефоне
// удары.
import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// Вызывается на main при получении пакета ударов от часов — ДО того,
    /// как батч применяется к ShotQueue (хук для UI/диагностики, само
    /// применение WatchBridge делает самостоятельно, см. applyBatch).
    var onShotBatch: ((WatchShotBatch) -> Void)?

    private override init() {
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
            self?.applyBatch(batch)
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
    private func applyBatch(_ batch: WatchShotBatch) {
        Task {
            // AuthService — @MainActor (зеркалит FirebaseAuth) — читаем
            // через await, а не вытаскиваем из nonisolated-контекста.
            guard let uid = await AuthService.currentUserId, !uid.isEmpty else {
                #if DEBUG
                print("WatchBridge: нет авторизованного пользователя — батч ударов от часов отброшен")
                #endif
                return
            }
            guard let round = try? await RoundsService.getRound(roundId: batch.roundId) else {
                #if DEBUG
                print("WatchBridge: не удалось прочитать раунд \(batch.roundId) для мерджа батча с часов")
                #endif
                return
            }

            var acceptedEntries: [WatchShotReceiptEntry] = []
            for entry in batch.entries {
                let holeIndex = entry.holeNumber - 1
                guard round.holes.indices.contains(holeIndex) else { continue }
                let existingShots = round.holes[holeIndex].shots[uid]
                let fullClubs = (existingShots?.resolvedClubs ?? []) + entry.clubs
                let fullDistances = (existingShots?.resolvedDistances ?? []) + Array(repeating: 0, count: entry.clubs.count)

                let outcome = await ShotQueue.shared.recordShotQueued(
                    roundId: batch.roundId, holeIndex: holeIndex, targetUid: uid,
                    clubs: fullClubs, distances: fullDistances
                )
                switch outcome {
                case .synced, .queued:
                    // Обе ветки означают, что удар ДУРАБЕЛЬНО осел на
                    // телефоне (ShotQueue пишет на диск ДО попытки сети) —
                    // подтверждаем часам. .rejected — сервер окончательно
                    // отверг запись, подтверждать нечего, часы повторят.
                    acceptedEntries.append(WatchShotReceiptEntry(holeNumber: entry.holeNumber, acceptedCount: entry.clubs.count))
                case .rejected:
                    #if DEBUG
                    print("WatchBridge: recordShot отклонён сервером для лунки \(entry.holeNumber)")
                    #endif
                }
            }
            guard !acceptedEntries.isEmpty else { return }
            send(receipt: WatchShotReceipt(roundId: batch.roundId, entries: acceptedEntries))
        }
    }
}
