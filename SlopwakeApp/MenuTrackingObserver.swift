import AppKit

@MainActor
final class MenuTrackingObserver: NSObject {
    private let notificationCenter: NotificationCenter
    private let didBeginTracking: @MainActor () -> Void
    private let didEndTracking: @MainActor () -> Void

    init(
        notificationCenter: NotificationCenter = .default,
        didBeginTracking: @escaping @MainActor () -> Void,
        didEndTracking: @escaping @MainActor () -> Void
    ) {
        self.notificationCenter = notificationCenter
        self.didBeginTracking = didBeginTracking
        self.didEndTracking = didEndTracking
        super.init()

        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidBeginTracking(_:)),
            name: NSMenu.didBeginTrackingNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(menuDidEndTracking(_:)),
            name: NSMenu.didEndTrackingNotification,
            object: nil
        )
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    @objc
    private func menuDidBeginTracking(_: Notification) {
        didBeginTracking()
    }

    @objc
    private func menuDidEndTracking(_: Notification) {
        didEndTracking()
    }
}
