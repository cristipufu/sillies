import Foundation

/// The UI and Chat depend on capabilities; app composition supplies the local implementation.
public protocol ConversationRepository: Sendable {
  func open(_ owner: ConversationOwner) async throws -> ConversationSnapshot
  func save(_ update: ConversationUpdate) async throws
  func page(_ request: ConversationPageRequest) async throws -> ConversationPage
  func checkpoint(_ handle: ConversationHandle) async throws -> ConversationMemorySnapshot
  func advanceCheckpoint(_ update: ConversationMemoryUpdate) async throws -> Bool
  func search(_ request: ConversationSearchRequest) async throws -> [ConversationSearchMatch]
  func conversations() async throws -> [ConversationHeader]
  func clear(_ handle: ConversationHandle) async throws -> ConversationSnapshot
}

public enum ConversationStorageError: Error, LocalizedError {
  case changed, messageUnavailable, unsupportedVersion, invalidData
  public var errorDescription: String? {
    switch self {
    case .changed: String(localized: "This conversation changed. Reopen it before continuing.")
    case .messageUnavailable: String(localized: "The original message is no longer available.")
    case .unsupportedVersion:
      String(
        localized:
          "This conversation needs a newer version of Sillies. Your messages are preserved.")
    case .invalidData:
      String(localized: "The conversation could not be read. Your messages are preserved.")
    }
  }
}

public enum ConversationMode: String, Sendable { case chat, talk }
