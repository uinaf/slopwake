import SlopwakeCore
import SwiftUI

@main
@MainActor
struct SlopwakeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = WakeMenuModel(
        controller: WakeServices.shared.controller,
        automaticMonitor: WakeServices.shared.automaticMonitor,
        batteryMonitor: WakeServices.shared.batteryMonitor,
        preferenceStore: WakeServices.shared.preferences,
        loginItemController: WakeServices.shared.loginItemController,
        startsServices: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    )

    var body: some Scene {
        MenuBarExtra {
            WakeMenu(model: model)
                .font(.system(.body, design: .monospaced))
        } label: {
            Image(systemName: model.isHolding ? "bolt.fill" : "bolt")
                .accessibilityLabel("slopwake · \(model.statusText)")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct WakeMenu: View {
    let model: WakeMenuModel

    var body: some View {
        Label(model.statusText, systemImage: statusSymbol)
            .font(.system(.body, design: .monospaced))
            .foregroundStyle(model.isHolding ? UinafTokens.phosphor : Color.secondary)

        ForEach(model.policyState.sources, id: \.surface) { source in
            Text("\(source.surface.displayName.lowercased()) · \(source.evidence.rawValue)")
                .font(.system(.caption, design: .monospaced))
        }

        if let errorMessage = model.errorMessage {
            Text(errorMessage)
                .font(.system(.caption, design: .monospaced))
            if model.wakeErrorMessage != nil {
                Button("retry wake hold", action: model.retryWakeHold)
            }
        }

        Divider()

        manualMenu
        automaticMenu
        detectorMenu
        optionMenu

        Divider()

        Button("quit slopwake", action: model.quit)
            .keyboardShortcut("q")
    }

    private var manualMenu: some View {
        Menu("manual hold") {
            ForEach(ManualHoldDuration.allCases, id: \.rawValue) { duration in
                Button(duration.displayName) {
                    model.startManualHold(duration)
                }
            }
            if model.policyState.isManualActive {
                Divider()
                Button("end manual hold", action: model.endManualHold)
            }
        }
    }

    private var automaticMenu: some View {
        Menu("automatic detection") {
            if model.policyState.isAutomaticPaused {
                Button("resume", action: model.resumeAutomatic)
                Divider()
            }
            Button("pause for 30 minutes") {
                model.pauseAutomatic(.thirtyMinutes)
            }
            Button("pause for 1 hour") {
                model.pauseAutomatic(.oneHour)
            }
            Button("pause until resumed", action: model.pauseAutomaticUntilResumed)
        }
    }

    private var detectorMenu: some View {
        Menu("detectors") {
            ForEach(AgentSurface.allCases, id: \.self) { surface in
                Toggle(
                    surface.displayName.lowercased(),
                    isOn: Binding(
                        get: { model.preferences.enabledSurfaces.contains(surface) },
                        set: { model.setSurface(surface, enabled: $0) }
                    )
                )
            }
        }
    }

    private var optionMenu: some View {
        Menu("options") {
            Toggle(
                "keep display awake",
                isOn: Binding(
                    get: { model.preferences.preventsDisplaySleep },
                    set: { enabled in
                        model.setPreventsDisplaySleep(enabled)
                    }
                )
            )

            Picker(
                "battery cutoff",
                selection: Binding(
                    get: { model.preferences.batteryCutoffPercentage },
                    set: { cutoff in
                        model.setBatteryCutoffPercentage(cutoff)
                    }
                )
            ) {
                ForEach(WakePreferences.supportedBatteryCutoffs, id: \.self) { cutoff in
                    Text(cutoff.map { "\($0)%" } ?? "off").tag(cutoff)
                }
            }

            Toggle(
                "start at login",
                isOn: Binding(
                    get: { model.startsAtLogin },
                    set: { enabled in
                        model.setStartsAtLogin(enabled)
                    }
                )
            )
        }
    }

    private var statusSymbol: String {
        model.isHolding ? "circle.fill" : "circle"
    }

}
