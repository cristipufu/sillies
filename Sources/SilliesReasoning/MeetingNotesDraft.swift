/// Content strategies share admission and lifecycle without sharing mutable draft state.
protocol MeetingNotesDraft: Sendable {
  var actionLanguageIdentifier: String? { get }
  mutating func append(_ source: MeetingTranscriptSlice) async throws
  func finish(actions: [String]) async throws -> LocalNotes
}
