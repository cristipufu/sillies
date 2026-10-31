import Foundation
import SilliesTextModels
import Testing

@testable import SilliesApp

@Test func multilingualNotesUseSelectedBackendAndRetainOnlySourceBackedActions() async throws {
  let backend = NotesBackend()
  let service = LocalReasoningService(backend: backend)
  let notes = await service.notes(
    for: "Ștefan trimite raportul mâine la 14:30.", kind: .listen, fallback: "Recording",
    localeIdentifier: "ro")
  #expect(notes.source == .generated)
  #expect(notes.summary == "Raportul va fi trimis mâine.")
  #expect(notes.actions == ["Ștefan trimite raportul mâine la 14:30."])
  #expect(await backend.instructions.contains { $0.contains("Romanian") })
}

@Test func invalidDownloadedOutputFallsBackWithoutReplacingTheSourceWithInventedNotes() async {
  let service = LocalReasoningService(backend: InvalidBackend())
  let notes = await service.notes(
    for: "Ștefan trimite raportul mâine.", kind: .listen, fallback: "Recording",
    localeIdentifier: "ro")
  #expect(notes.source == .extracted)
  #expect(notes.actions.isEmpty)
  #expect(!notes.notice.isEmpty)
}

@Test func reasoningJSONAcceptsOnlyAnObjectAndRejectsThinkingOrTruncatedOutput() throws {
  #expect(
    try ReasoningOutput.clean(
      "```json\n{\"summary\":\"Mâine\",\"explanation\":\"\"}\n```", format: .notes)
      == "{\"summary\":\"Mâine\",\"explanation\":\"\"}")
  for invalid in ["Here is your result: {}", "{\"summary\":", "<think>secret</think>{}"] {
    #expect(throws: TextModelError.self) { try ReasoningOutput.clean(invalid, format: .notes) }
  }
}

@Test func cancelledReasoningWaitersDoNotBlockFollowingWriting() async throws {
  let gate = ReasoningTurnGate()
  try await gate.acquire(.background)
  let waiting = Task { try await gate.acquire(.interactive) }
  waiting.cancel()
  await #expect(throws: CancellationError.self) { try await waiting.value }
  await gate.release()
  #expect(await gate.tryAcquire())
  await gate.release()
}

private actor NotesBackend: ReasoningBackend {
  private(set) var instructions: [String] = []
  func availabilityNotice(localeIdentifier: String?) -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) throws -> String {
    instructions.append(request.instructions)
    switch format {
    case .notes: return #"{"summary":"Raportul va fi trimis mâine.","explanation":""}"#
    case .actions:
      return #"{"passages":["Ștefan trimite raportul mâine la 14:30.","Alex va plăti 100 lei."]}"#
    default: throw TextModelError.invalidResponse
    }
  }
}
private struct InvalidBackend: ReasoningBackend {
  func availabilityNotice(localeIdentifier: String?) async -> String? { nil }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    "incomplete JSON"
  }
}
