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
}

@MainActor
final class LoginItemController: LoginItemControlling {
    private let service = SMAppService.mainApp

    var state: LoginItemState {
        switch service.status {
        case .notRegistered: .disabled
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            switch service.status {
            case .notRegistered:
                try service.register()
            case .enabled, .requiresApproval:
                break
            case .notFound:
                throw LoginItemError.unavailable
            @unknown default:
                throw LoginItemError.unavailable
            }
        } else {
            switch service.status {
            case .notRegistered:
                break
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notFound:
                throw LoginItemError.unavailable
            @unknown default:
                throw LoginItemError.unavailable
            }
        }
    }
}
