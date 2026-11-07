import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault

/// Long synthetic transcripts and bounded binary attachments exercise storage, not recognition quality.
enum VaultMeetingFixture {
  private static let transcriptTurns = 300
  private static let attachmentBytes = 65_536

  static func seed(_ library: VaultLibrary, target: Int, seconds: Double) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(seconds))
    var count = try await library.snapshot().page.total
    while count < target, ContinuousClock.now < deadline {
      let record = makeRecord(count)
      let attachment = VaultAttachment(
        filename: "meeting-\(count).bin",
        data: Data(repeating: UInt8(count % 251), count: attachmentBytes))
      _ = try await library.commit(.init(records: [.insert(record)], attachments: [attachment]))
      count += 1
    }
    try VaultScaleBenchmark.emit(
      Progress(records: count, target: target, complete: count == target))
  }

  private static func makeRecord(_ index: Int) -> SessionRecord {
    let transcript = (0..<transcriptTurns).map { turn in
      "Speaker \(turn % 4): During project \(index), discussion \(turn), we reviewed navigation, search, accessibility and backup recovery. The owner will verify the saved decision and report results at the next meeting."
    }.joined(separator: "\n")
    var record = SessionRecord(
      kind: .record,
      origin: .init(
        characterID: "pogo", characterName: "Pogo",
        source: .init(appName: "Synthetic meeting", windowTitle: "Project \(index)")),
      content: .init(
        text: .init(transcript: transcript),
        notes: .init(summary: "Reviewed project \(index), decisions and recovery.")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: Double(index)), durationSeconds: 3_600)
    )
    record.audioFilename = "meeting-\(index).bin"
    return record
  }
  private struct Progress: Encodable {
    let records: Int
    let target: Int
    let complete: Bool
  }
}
