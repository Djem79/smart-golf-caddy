// ios/SmartGolfCaddy/Services/WatchBridge.swift
// Мост iPhone → Apple Watch поверх WatchConnectivity. import WatchConnectivity
// разрешён ТОЛЬКО в этом файле и в SmartGolfCaddyWatch/Services/PhoneBridge.swift
// (см. CLAUDE.md). Снимок раунда шлём через updateApplicationContext —
// последнее состояние всегда актуально, старые снимки перезаписываются без
// накопления очереди. Удары от часов приходят через didReceiveUserInfo —
// это гарантированная доставка со стороны часов, переживающая недоступность
// связи.
import Foundation
import WatchConnectivity

final class WatchBridge: NSObject, WCSessionDelegate {
    static let shared = WatchBridge()

    /// Вызывается на main при получении пакета ударов от часов.
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
            print("WatchBridge: не удалось отправить снимок раунда: \(error)")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("WatchBridge: ошибка активации сессии: \(error)")
        }
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
        guard let batch = WatchShotBatch(payload: userInfo) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onShotBatch?(batch)
        }
    }
}
