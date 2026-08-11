import AppKit
import SlopwakeCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        WakeServices.shared.controller.stop()
    }
}

@MainActor
final class WakeServices {
    static let shared = WakeServices()

    let controller = CaffeinateController()
    let automaticMonitor = AutomaticWakeMonitor()

    private init() {}
}
