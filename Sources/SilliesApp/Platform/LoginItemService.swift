import Foundation
import ServiceManagement

enum LoginItemStatus: Sendable { case disabled, enabled, requiresApproval, unavailable }
enum LoginItemPreference: Sendable { case enabled, disabled }

protocol LoginItemServicing: Sendable {
  func status() async -> LoginItemStatus
  func update(_ preference: LoginItemPreference) async throws -> LoginItemStatus
}

actor LoginItemService: LoginItemServicing {
  func status() -> LoginItemStatus {
    switch SMAppService.mainApp.status {
    case .enabled: .enabled
    case .requiresApproval: .requiresApproval
    case .notRegistered: .disabled
    case .notFound: .unavailable
    @unknown default: .unavailable
    }
  }

  func update(_ preference: LoginItemPreference) throws -> LoginItemStatus {
    dispatchPrecondition(condition: .notOnQueue(.main))
    switch preference {
    case .enabled:
      if status() != .enabled && status() != .requiresApproval {
        try SMAppService.mainApp.register()
      }
    case .disabled: try SMAppService.mainApp.unregister()
    }
    return status()
  }
}
