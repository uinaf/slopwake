import Foundation
import Observation
import SlopwakeCore

@MainActor
@Observable
final class WakePreferencesStore {
    private(set) var value: WakePreferences

    @ObservationIgnored
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        value = WakePreferences.load(from: defaults)
    }

    func setSurface(_ surface: AgentSurface, enabled: Bool) {
        if enabled {
            value.enabledSurfaces.insert(surface)
        } else {
            value.enabledSurfaces.remove(surface)
        }
        persist()
    }

    func setPreventsDisplaySleep(_ enabled: Bool) {
        value.preventsDisplaySleep = enabled
        persist()
    }

    func setBatteryCutoffPercentage(_ percentage: Int?) {
        value.batteryCutoffPercentage = WakePreferences.normalizedBatteryCutoffPercentage(
            percentage
        )
        persist()
    }

    func setStartsAtLogin(_ enabled: Bool) {
        value.startsAtLogin = enabled
        persist()
    }

    private func persist() {
        value.save(to: defaults)
    }
}
