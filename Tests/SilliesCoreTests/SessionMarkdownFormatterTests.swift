import Foundation
import SilliesCore
import Testing

@Test func sessionMarkdownPreservesAllExportSectionsAndTheirOrder() throws {
  let id = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000123"))
  let date = try #require(ISO8601DateFormatter().date(from: "2026-10-25T10:30:00Z"))
  let suggestion = MeetingSuggestion(
    question: "Who owns this?", evidence: "Owner undecided.", elapsed: 61)
  let record = SessionRecord(
    kind: .participate,
    origin: .init(
      characterID: "mochi", characterName: "Mochi",
      source: .init(
        appName: "Meeting", bundleIdentifier: "example.meeting", windowTitle: "Planning")),
    content: .init(
      text: .init(
        transcript: "Keep the transcript.", extractedText: "Visible text",
        stashedItems: ["https://example.com"]),
      notes: .init(
        summary: "Ship Friday.", actionItems: ["Review draft"],
        explanation: "Review before shipping.", suggestions: [suggestion]),
      attachments: .init(imageFilename: "snapshot.png", audioFilename: "meeting.m4a"),
      processing: .init(
        summaryPending: true,
        failure: .init(category: .captureInterrupted, message: "Input disconnected."),
        note: "Generated locally.")),
    metadata: .init(id: id, createdAt: date, durationSeconds: 125, languageIdentifier: "en-US"))
  #expect(record.id == id)
  #expect(record.bundleIdentifier == "example.meeting")
  #expect(record.imageFilename == "snapshot.png")
  #expect(record.summaryPending)
  #expect(record.suggestions == [suggestion])
  let expected = """
    # Meeting — Planning
    - **Skill**: Participate
    - **Companion**: Mochi
    - **Date**: 2026-10-25T10:30:00Z
    - **Duration**: 02:05
    - **Notes language**: English (United States)

    ## Summary
    Ship Friday.

    Session issue: Input disconnected.

    Audio: meeting.m4a

    Generated locally.

    ## Explanation
    Review before shipping.

    ## Meeting Suggestions
    - [01:01] Who owns this?
      Source: Owner undecided.

    ## Action Items
    - [ ] Review draft

    ## Transcript
    Keep the transcript.

    ## Extracted Window Text
    ```
    Visible text
    ```

    ## Stashed Items
    - https://example.com
    """
  #expect(SessionMarkdownFormatter.format(record, locale: Locale(identifier: "en_US")) == expected)
  #expect(
    try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record)) == record)
}

@Test func sessionMarkdownOmitsAbsentSections() {
  let record = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Microphone")),
    metadata: .init(createdAt: Date(timeIntervalSince1970: 0)))
  #expect(
    SessionMarkdownFormatter.format(record) == """
      # Microphone · Record
      - **Skill**: Record
      - **Companion**: Mochi
      - **Date**: 1970-01-01T00:00:00Z
      """)
}
