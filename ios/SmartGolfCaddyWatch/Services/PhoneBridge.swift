// ios/SmartGolfCaddyWatch/Services/PhoneBridge.swift
// Мост Apple Watch → iPhone поверх WatchConnectivity. import WatchConnectivity
// разрешён ТОЛЬКО в этом файле и в SmartGolfCaddy/Services/WatchBridge.swift
// (см. CLAUDE.md). Снимок раунда приходит через didReceiveApplicationContext
// (перезаписывается телефоном по мере игры). Удары шлём через
// transferUserInfo — гарантированная доставка, переживает временную
// недоступность телефона (в отличие от sendMessage). Квитанции о приёме
// батча приходят тем же каналом в обратную сторону (didReceiveUserInfo) —
// применяются к WatchShotQueue напрямую (файловая очередь, не
// @Observable-состояние — MainActor-хоп не нужен).
//
// ВАЖНО: делегатные методы WCSession приходят на фоновом потоке — публикация
// в @Observable-свойства обязана идти через MainActor.
import Foundation
import Observation
import WatchConnectivity

@Observable
@MainActor
final class PhoneBridge: NSObject, WCSessionDelegate {
    static let shared = PhoneBridge()

    var latestSnapshot: WatchRoundSnapshot?
    var isReachable: Bool = false

    private override init() {
        super.init()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// activationState-гейт обязателен: activate() асинхронна, а
    /// transferUserInfo на неактивированной сессии молча не ставит трансфер
    /// в очередь (activationState останется .notActivated, а
    /// outstandingUserInfoTransfers — пустым) — обнаружено живой проверкой
    /// Task 4: flush() вызывается сразу после activate() в WatchRootView
    /// (в т.ч. для хвостов, переживших перезапуск часов), и без этого гейта
    /// самая первая попытка отправки после холодного старта тихо терялась
    /// бы. WatchBridge.send(snapshot:) на телефоне уже страхуется тем же
    /// способом — здесь то же самое, в обратную сторону.
    func send(batch: WatchShotBatch) {
        guard WCSession.isSupported() else { return }
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(batch.payload)
    }

    /// Часы вызывают flush через это — обёртка над WatchShotQueue.shared,
    /// инжектируемая в WatchShotQueue.flush(via:) из вью-слоя (см.
    /// WatchRootView). Отдельный метод, а не прямой `PhoneBridge.shared.send`
    /// в вызывающем коде — чтобы точка вызова flush не завязывалась на
    /// сигнатуру send(batch:) напрямую.
    func flushShotQueue() {
        WatchShotQueue.shared.flush { [weak self] batch in self?.send(batch: batch) }
    }

    // MARK: - WCSessionDelegate

    // `self` внутри nonisolated-делегатного метода actor-isolated класса не
    // даёт прямого доступа к @MainActor-свойствам без хопа, поэтому пишем
    // через PhoneBridge.shared — тот же единственный экземпляр (private
    // init, синглтон), просто адресуемся к нему через MainActor-контекст.
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        #if DEBUG
        if let error {
            print("PhoneBridge: ошибка активации сессии: \(error)")
        }
        #endif
        let reachable = session.isReachable
        Task { @MainActor in
            PhoneBridge.shared.isReachable = reachable
            // Активация асинхронна — самая первая попытка flush() в
            // WatchRootView.task (сразу после activate(), для хвостов,
            // переживших перезапуск часов) могла молча не отправиться, т.к.
            // send(batch:) теперь гейтит по activationState (см. её
            // комментарий). Как только активация реально завершилась,
            // пробуем ещё раз — это и есть тот самый повтор.
            if activationState == .activated {
                PhoneBridge.shared.flushShotQueue()
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            PhoneBridge.shared.isReachable = reachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchRoundSnapshot(payload: applicationContext) else {
            #if DEBUG
            print("PhoneBridge: не удалось разобрать снимок раунда: \(applicationContext)")
            #endif
            return
        }
        Task { @MainActor in
            PhoneBridge.shared.latestSnapshot = snapshot
        }
    }

    /// Квитанция о приёме батча ударов от телефона — снимает/подрезает
    /// соответствующие слоты WatchShotQueue (см. её markConfirmed).
    /// Файловая очередь не @Observable — MainActor-хоп не нужен, но
    /// делегатный метод в любом случае nonisolated (приходит на фоновом
    /// потоке), поэтому не трогаем self.latestSnapshot/isReachable здесь.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let receipt = WatchShotReceipt(payload: userInfo) else {
            #if DEBUG
            print("PhoneBridge: не удалось разобрать квитанцию от телефона: \(userInfo)")
            #endif
            return
        }
        for entry in receipt.entries {
            WatchShotQueue.shared.markConfirmed(roundId: receipt.roundId, holeNumber: entry.holeNumber, acceptedCount: entry.acceptedCount)
        }
    }
}
