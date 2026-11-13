import Foundation

/// One job owns source admission, background turns and cancellation for either notes workflow.
struct MeetingNotesGenerator {
  let inference: NotesInference
  func generate<Draft: MeetingNotesDraft>(_ source: String, using initialDraft: Draft) async throws
    -> LocalNotes
  {
    var draft = initialDraft
    var remainder = source[...]
    var offset = 0
    var actions: [String] = []
    let slicer = MeetingTranscriptSlicer(inference: inference)
    while !remainder.isEmpty {
      try Task.checkCancellation()
      let slice = try await slicer.slice(remainder, offset: offset)
      if !slice.text.allSatisfy(\.isWhitespace) {
        try await draft.append(slice)
        actions += try await LocalActionEvidence.extract(
          from: slice, localeIdentifier: draft.actionLanguageIdentifier, inference: inference)
      }
      offset += slice.text.count
      remainder = remainder.dropFirst(slice.text.count)
    }
    var seen: Set<String> = []
    return try await draft.finish(
      actions: actions.filter { seen.insert($0).inserted })
  }
}
