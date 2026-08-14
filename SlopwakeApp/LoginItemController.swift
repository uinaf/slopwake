import ServiceManagement

enum LoginItemState: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable
}

enum LoginItemError: Error {
    case unavailable
}

@MainActor
protocol LoginItemControlling: AnyObject {
    var state: LoginItemState { get }

    func setEnabled(_ enabled: Bool) throws
    func openSystemSettings()
}

@MainActor
protocol LoginItemServicing: AnyObject {
    var status: SMAppService.Status { get }

    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemServicing {}

@MainActor
final class LoginItemController: LoginItemControlling {
    private let service: any LoginItemServicing

    init(service: any LoginItemServicing = SMAppService.mainApp) {
        self.service = service
    }

    var state: LoginItemState {
        switch service.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .disabled
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch service.status {
            case .notRegistered, .notFound:
                // macOS 26 can report notFound before the first successful main-app registration.
                try service.register()
            case .enabled, .requiresApproval:
                break
            @unknown default:
                throw LoginItemError.unavailable
            }
        } else {
            switch service.status {
            case .notRegistered, .notFound:
                break
            case .enabled, .requiresApproval:
                try service.unregister()
            @unknown default:
                throw LoginItemError.unavailable
            }
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
