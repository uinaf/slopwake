import SwiftUI

@main
@MainActor
struct SlopwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = WakeMenuModel(
        controller: WakeServices.shared.controller,
        automaticMonitor: WakeServices.shared.automaticMonitor
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
    let model: WakeMenuModel

    var body: some View {
        Text(statusText)
            .font(.system(.body, design: .monospaced))

        ForEach(model.automaticState.sources, id: \.surface) { source in
            Text("\(source.surface.displayName) — \(source.evidence.rawValue)")
                .font(.system(.caption, design: .monospaced))
        }

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.system(.caption, design: .monospaced))
        }

        Divider()

        if model.manualHoldRequested {
            Button("End Manual Hold", action: model.stop)
        } else {
            Button("Keep Awake Manually", action: model.start)
        }

        Divider()

        Button("Quit slopwake", action: model.quit)
            .keyboardShortcut("q")
    }

    private var statusText: String {
        if !model.isHolding {
            if model.automaticState.isCeilingLimited && !model.manualHoldRequested {
                return "Idle — automatic limit reached"
            }
            if model.manualHoldRequested || model.automaticState.shouldHold {
                return "Idle — wake hold unavailable"
            }
            return "Idle — sleep allowed"
        }
        if model.manualHoldRequested && model.automaticState.shouldHold {
            return "Awake — manual + automatic"
        }
        if model.manualHoldRequested {
            return "Awake — manual hold"
        }
        if model.automaticState.shouldHold {
            return "Awake — automatic hold"
        }
        return "Awake — releasing hold"
    }
}
