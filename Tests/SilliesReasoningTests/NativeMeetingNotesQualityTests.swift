import Foundation
import SilliesCore
import SilliesTextModels
import Testing

@testable import SilliesReasoning

/// Opt-in synthetic inputs only. Review the printed outputs against the source, beyond assertions.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_TOPIC_NOTES_QUALITY_CHECK"] == "1"))
func nativeMeetingTopicsPreserveCorrectionsAndSeparateAgendaFromOutcomes() async throws {
  let backend = TopicQualityBackend()
  guard await backend.availabilityNotice(localeIdentifier: "en") == nil else {
    print("TOPIC QUALITY UNAVAILABLE: Apple on-device inference is not available.")
    return
  }
  let source = """
    Alex: For the launch, I propose May 9. This is a proposal, not an agreed date.
    Mina: Our approved marketing budget is 900 credits. We will use it for the existing campaign.
    Alex: We still need someone to own customer support; no owner is assigned yet.
    Mina: The campaign already has approved artwork for the product page and the newsletter. The message explains how the product helps people organize their saved material. There is no request for a second campaign or another advertising channel.
    Alex: The launch checklist includes the product page, the release announcement and the existing help article. These describe the same release. The help article needs to explain where people find their saved recordings and how they can correct a transcript.
    Mina: The campaign can use screenshots from the current release. We do not need new photography. The product page should use the approved colors and the same wording as the announcement, so people see one consistent explanation.
    Alex: Customer support is the open issue. People may ask how long processing takes and whether a recording is saved before notes finish. The help article can explain that the transcript remains available even if generated notes are unavailable. That does not settle who answers support requests.
    Mina: The approved marketing budget covers the current plan. Extra promotional work would need a separate discussion. We have not approved extra spending, another agency or a change to the campaign budget in this meeting.
    Alex: The release checks cover opening a saved recording, reading the transcript and returning to the conversation. The checklist also includes cancellation while notes are being prepared. These are existing checks, rather than new product features for the announcement.
    Mina: The announcement should describe what is already available. It should not imply that a future integration has shipped. An unfinished integration can be discussed later; it is outside this launch campaign and there is no commitment to a date for it here.
    Alex: For support, a clear contact route matters more than adding another help page. The current article can point people to the existing contact route. We still have not assigned ownership of those incoming questions.
    Mina: The release announcement and the newsletter share the same source copy. If the product description changes during review, the final wording should stay consistent in both places. That is a review principle; no additional author is being assigned now.
    Alex: The checklist is a way to verify the current release before announcing it. We are not adding another release milestone or changing the approved marketing plan. The unresolved timing question is whether the original launch proposal leaves enough time for the review.
    Mina: There is no objection to the existing campaign scope or the approved artwork. The open items are the final launch date and support ownership. A proposal about timing should not be written up as an agreement until we actually agree on it.
    Alex: Returning to launch timing: May 9 is too early. I propose May 11 instead.
    Mina: Agreed. May 11 is the final launch date, replacing the earlier May 9 proposal.
    Alex: I will send the revised launch plan on Thursday. Support ownership remains unresolved.
    """
  let requests: [LocalNotesRequest] = [
    .init(
      source: source, kind: .listen, fallback: "Existing summary",
      personalNotes: "Agenda: launch, pricing, support. Did we approve an acquisition?",
      localeIdentifier: "en"),
    .init(
      source:
        "We agreed to deliver the report on Friday. Alex will review the draft tomorrow. Who owns the customer follow-up? We have not assigned that task.",
      kind: .record, fallback: "Existing summary",
      personalNotes: "Agenda: report and customer follow-up.", localeIdentifier: "fr"),
    .init(
      source: "We agreed to ship the report on Friday. Alex will review the draft tomorrow.",
      kind: .record, fallback: "Existing summary", localeIdentifier: "fr"),
  ]
  for request in requests {
    print("TOPIC QUALITY SOURCE: \(request.source)")
    let notes = await LocalReasoningService(backend: backend).notes(for: request)
    print(
      "TOPIC QUALITY RESULT \(request.localeIdentifier ?? "auto"): \(notes.summary) | actions=\(notes.actions) | provenance=\(notes.source)"
    )
    #expect(notes.source == .extracted)
    #expect(!notes.summary.isEmpty)
    #expect(notes.notice.isEmpty)
    for line in notes.summary.split(separator: "\n") where line.hasPrefix("• ") {
      #expect(request.source.contains(line.dropFirst("• ".count)))
    }
    #expect(notes.actions.allSatisfy { request.source.contains($0) })
    #expect(notes.actions.contains { $0.contains("Alex") })
    #expect(notes.summary.components(separatedBy: "\n\n").count > 1)
    #expect(!notes.summary.localizedCaseInsensitiveContains("acquis"))
    #expect(notes.actions.allSatisfy { !$0.contains("no owner") && !$0.contains("unresolved") })
    if request.localeIdentifier == "en" {
      #expect(notes.summary.contains("11"))
      #expect(notes.summary.contains("900"))
      #expect(notes.actions.allSatisfy { !$0.contains("final launch date") })
      #expect(
        notes.actions.contains { $0.contains("I will send the revised launch plan on Thursday.") })
    }
  }
}

private struct TopicQualityBackend: ReasoningBackend, ConversationBudgeting {
  private let apple = AppleReasoningBackend()
  var meetingNotesStyle: MeetingNotesStyle { apple.meetingNotesStyle }
  var contextWindowTokens: Int { apple.contextWindowTokens }
  var conversationPolicy: ConversationPolicy { apple.conversationPolicy }
  var generationProfile: TextGenerationProfile { apple.generationProfile }
  func availabilityNotice(localeIdentifier: String?) async -> String? {
    await apple.availabilityNotice(localeIdentifier: localeIdentifier)
  }
  func inputTokenCount(_ request: TextGenerationRequest) async throws -> Int {
    try await apple.inputTokenCount(request)
  }
  func generate(_ request: TextGenerationRequest, format: ReasoningFormat) async throws -> String {
    do {
      let result = try await apple.generate(request, format: format)
      print("TOPIC QUALITY RAW \(format): \(result)")
      return result
    } catch {
      print("TOPIC QUALITY FAILURE \(format): \(String(reflecting: error))")
      throw error
    }
  }
}
