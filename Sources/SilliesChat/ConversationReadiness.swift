import Foundation
import SilliesCore

/// Setup and session admission share the same checks without opening devices or loading models.
package struct ConversationReadiness: Sendable {
  package enum Requirement: String, CaseIterable, Identifiable, Sendable {
    case replyModel, microphone, recognition, voice
    package var id: Self { self }
  }
  package struct Check: Sendable, Identifiable {
    package let requirement: Requirement
    package let result: ChatReadiness
    package var id: Requirement { requirement }
    package init(requirement: Requirement, result: ChatReadiness) {
      self.requirement = requirement
      self.result = result
    }
  }

  package let checks: [Check]
  package var admission: ChatReadiness {
    checks.first { check in
      if case .available = check.result { return false }
      return true
    }?.result ?? .available
  }

  package static func evaluate(
    services: ChatServices, language: String, mode: ConversationMode
  ) async -> Self {
    let text = await services.conversation.availabilityNotice(localeIdentifier: language)
    var checks: [Check] = [
      .init(
        requirement: .replyModel,
        result: text.map { .needsSetup(.textUnavailable($0)) } ?? .available)
    ]
    guard mode == .talk, !Task.isCancelled else { return .init(checks: checks) }
    checks.append(
      .init(
        requirement: .microphone,
        result: services.microphonePermission().map { .permissionRequired($0) } ?? .available))
    checks.append(
      .init(
        requirement: .recognition, result: await recognition(services: services, language: language)
      ))
    guard !Task.isCancelled else { return .init(checks: checks) }
    let voice = await services.speech.availabilityNotice(language: language)
    checks.append(
      .init(
        requirement: .voice,
        result: voice.map { .needsSetup(.voiceUnavailable($0)) } ?? .available))
    return .init(checks: checks)
  }

  package static func recognition(services: ChatServices, language: String) async -> ChatReadiness {
    do {
      let catalog = try await services.loadLanguages()
      guard
        catalog.installedLanguage(matching: language) != nil
          || catalog.installed.contains(where: \.isAutomatic)
      else {
        return .needsSetup(
          .recognitionUnavailable(
            String(
              localized:
                "This speech model cannot recognize the selected language. Choose another in Settings → Speech & Meetings."
            )))
      }
      return .available
    } catch is CancellationError {
      return .unchecked
    } catch {
      return .needsSetup(.recognitionUnavailable(error.localizedDescription))
    }
  }
}
