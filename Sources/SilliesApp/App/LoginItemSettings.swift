import Foundation
import Observation

@MainActor @Observable
final class LoginItemSettings {
  private(set) var status: LoginItemStatus = .disabled
  private(set) var isUpdating = false
  private(set) var error: String?
  private let service: any LoginItemServicing

  init(service: any LoginItemServicing = LoginItemService()) { self.service = service }
  var requested: Bool { status == .enabled || status == .requiresApproval }

  func refresh() async {
    guard !isUpdating else { return }
    status = await service.status()
  }

  func update(_ preference: LoginItemPreference) async {
    guard !isUpdating else { return }
    isUpdating = true
    defer { isUpdating = false }
    error = nil
    do { status = try await service.update(preference) } catch {
      status = await service.status()
      self.error = error.localizedDescription
      fputs("Login item update failed: \(error)\n", stderr)
    }
  }
}
