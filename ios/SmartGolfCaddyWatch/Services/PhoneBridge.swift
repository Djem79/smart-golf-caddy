// ios/SmartGolfCaddyWatch/Services/PhoneBridge.swift
// Мост Apple Watch → iPhone поверх WatchConnectivity. import WatchConnectivity
// разрешён ТОЛЬКО в этом файле и в SmartGolfCaddy/Services/WatchBridge.swift
// (см. CLAUDE.md). Снимок раунда приходит через didReceiveApplicationContext
// (перезаписывается телефоном по мере игры). Удары шлём через
// transferUserInfo — гарантированная доставка, переживает временную
// недоступность телефона (в отличие от sendMessage).
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

    func send(batch: WatchShotBatch) {
        guard WCSession.isSupported() else { return }
        WCSession.default.transferUserInfo(batch.payload)
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
}
