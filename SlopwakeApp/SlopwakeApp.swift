import SwiftUI

@main
@MainActor
struct SlopwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = WakeMenuModel(
        controller: WakeServices.shared.controller
    )

    var body: some Scene {
        MenuBarExtra {
            WakeMenu(model: model)
        } label: {
            Image(systemName: model.isHolding ? "bolt.fill" : "bolt")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WakeMenu: View {
    @ObservedObject var model: WakeMenuModel

    var body: some View {
        Text(model.isHolding ? "Awake — manual hold" : "Idle — sleep allowed")
            .font(.system(.body, design: .monospaced))

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.system(.caption, design: .monospaced))
        }

        Divider()

        if model.isHolding {
            Button("Allow Sleep", action: model.stop)
        } else {
            Button("Keep Awake", action: model.start)
        }

        Divider()

        Button("Quit slopwake", action: model.quit)
            .keyboardShortcut("q")
    }
}
