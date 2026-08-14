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
        } label: {
            Image(model.isHolding ? "MenuActive" : "MenuIdle")
                .renderingMode(.template)
                .accessibilityLabel("slopwake · \(model.statusText)")
        }
        .menuBarExtraStyle(.menu)
    }
}

struct DetectorMenuGroup: Hashable {
    let title: String
    let desktop: AgentSurface
    let cli: AgentSurface

    static let all = [
        DetectorMenuGroup(title: "Codex", desktop: .codexDesktop, cli: .codexCLI),
        DetectorMenuGroup(title: "Claude", desktop: .claudeDesktop, cli: .claudeCLI),
        DetectorMenuGroup(title: "Cursor", desktop: .cursorDesktop, cli: .cursorCLI),
    ]
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

        Button("about slopwake", action: SlopwakeAboutPanel.present)

        Button("quit slopwake", action: model.quit)
            .keyboardShortcut("q")
            .onAppear(perform: model.refreshExternalState)
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
            ForEach(DetectorMenuGroup.all, id: \.self) { group in
                detectorSection(group.title, desktop: group.desktop, cli: group.cli)
            }
        }
    }

    @ViewBuilder
    private func detectorSection(
        _ title: String,
        desktop: AgentSurface,
        cli: AgentSurface
    ) -> some View {
        Section(title) {
            detectorToggle("desktop", systemImage: "macwindow", surface: desktop)
            detectorToggle("command line", systemImage: "terminal", surface: cli)
        }
    }

    private func detectorToggle(
        _ title: String,
        systemImage: String,
        surface: AgentSurface
    ) -> some View {
        Toggle(
            isOn: Binding(
                get: { model.preferences.enabledSurfaces.contains(surface) },
                set: { model.setSurface(surface, enabled: $0) }
            )
        ) {
            Label(title, systemImage: systemImage)
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

            if model.loginItemMessage != nil {
                Divider()
                Button("open Login Items settings", action: model.openLoginItemSettings)
            }
        }
    }

    private var statusSymbol: String {
        model.isHolding ? "circle.fill" : "circle"
    }

}
