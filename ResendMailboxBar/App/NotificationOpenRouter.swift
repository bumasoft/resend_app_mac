import Observation

@MainActor
@Observable
final class NotificationOpenRouter {
    static let shared = NotificationOpenRouter()

    var pendingPayload: NotificationRoutePayload?

    func enqueue(_ payload: NotificationRoutePayload) {
        pendingPayload = payload
    }

    @discardableResult
    func consume(_ payload: NotificationRoutePayload) -> Bool {
        guard pendingPayload == payload else { return false }
        pendingPayload = nil
        return true
    }
}
