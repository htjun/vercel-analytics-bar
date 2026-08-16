import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var label: String {
        switch self {
        case .disabled:
            "Off"
        case .enabled:
            "On"
        case .requiresApproval:
            "Approval required"
        case .unavailable:
            "Unavailable"
        }
    }

    var isEnabled: Bool {
        self == .enabled || self == .requiresApproval
    }
}

enum LaunchAtLoginError: Error, Equatable, LocalizedError {
    case registrationFailed
    case unregistrationFailed

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            "Analytics Menu Bar could not be added to Login Items."
        case .unregistrationFailed:
            "Analytics Menu Bar could not be removed from Login Items."
        }
    }
}

protocol LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus { get }
    func setEnabled(_ enabled: Bool) throws
}

struct SystemLaunchAtLoginManager: LaunchAtLoginManaging {
    var status: LaunchAtLoginStatus {
        switch SMAppService.mainApp.status {
        case .notRegistered:
            .disabled
        case .enabled:
            .enabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }

    func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw enabled ? LaunchAtLoginError.registrationFailed : LaunchAtLoginError.unregistrationFailed
        }
    }
}
