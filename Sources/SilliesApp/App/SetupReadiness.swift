import SilliesChat
import SilliesCore

/// Adds meeting permissions to the reusable conversation admission checks.
@MainActor struct SetupReadiness {
  struct Result {
    let requirements: [SetupRequirement]
    let microphoneLanguage: String?
  }
  let services: ChatServices
  let isGranted: @Sendable (SessionFailure.RecoveryAction) async -> Bool
  let meetingLanguage: () async throws -> String?

  func evaluate(activity: SetupActivity, language: String) async -> Result {
    guard activity != .companions else { return .init(requirements: [], microphoneLanguage: nil) }
    var microphoneLanguage: String? = language
    let mode: ConversationMode = activity == .talk ? .talk : .chat
    let readiness = await ConversationReadiness.evaluate(
      services: services, language: language, mode: mode)
    var requirements = readiness.checks.map(SetupRequirement.init)
    if activity == .meetings {
      requirements = requirements.map {
        var requirement = $0
        requirement.isOptional = true
        return requirement
      }
      let recognition: ChatReadiness
      do {
        microphoneLanguage = try await meetingLanguage()
        recognition =
          microphoneLanguage == nil
          ? .needsSetup(
            .recognitionUnavailable(
              String(localized: "Choose a meeting language in Speech & Meetings.")))
          : .available
      } catch {
        microphoneLanguage = nil
        recognition = .needsSetup(.recognitionUnavailable(error.localizedDescription))
      }
      requirements.append(.init(.init(requirement: .recognition, result: recognition)))
    }
    guard activity == .talk || activity == .meetings else {
      return .init(requirements: requirements, microphoneLanguage: nil)
    }
    requirements.removeAll { $0.id == .microphone }
    requirements.append(
      .init(permission: .openMicrophoneSettings, granted: await isGranted(.openMicrophoneSettings)))
    if activity == .meetings {
      requirements.append(
        .init(
          permission: .openScreenRecordingSettings,
          granted: await isGranted(.openScreenRecordingSettings)))
    }
    return .init(requirements: requirements, microphoneLanguage: microphoneLanguage)
  }
}
