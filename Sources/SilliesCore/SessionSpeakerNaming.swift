import Foundation

public struct SessionSpeakerIdentity: Identifiable, Equatable, Sendable {
  public let source: String
  public let number: Int
  public var id: String { "\(source):\(number)" }
  public var label: String { "\(source) · Speaker \(number)" }
}

/// Changes only speaker headers. Names never rewrite words spoken by the participants.
public enum SessionSpeakerNaming {
  private static let maximumNameLength = 80
  private struct Header {
    let prefix: Substring
    let source: String
    let numbers: [Int]
    let text: Substring
  }

  public static func speakers(in record: SessionRecord) -> [SessionSpeakerIdentity] {
    var seen: Set<String> = []
    return (record.originalSpeakerTranscript ?? record.transcript).split(separator: "\n")
      .compactMap(parse).flatMap { header in
        header.numbers.map { SessionSpeakerIdentity(source: header.source, number: $0) }
      }.filter { seen.insert($0.id).inserted }
  }

  public static func rename(
    _ identity: SessionSpeakerIdentity, to name: String, in record: SessionRecord
  ) -> SessionRecord {
    var record = record
    let name = String(
      name.trimmingCharacters(in: .whitespacesAndNewlines).filter { !$0.isNewline }.prefix(
        maximumNameLength))
    record.speakerNames[identity.id] = name.isEmpty ? nil : name
    let original = record.originalSpeakerTranscript ?? record.transcript
    record.originalSpeakerTranscript = original
    record.transcript = original.split(separator: "\n", omittingEmptySubsequences: false).map {
      line in
      guard let header = parse(line) else { return String(line) }
      guard
        header.numbers.contains(where: {
          record.speakerNames[SessionSpeakerIdentity(source: header.source, number: $0).id] != nil
        })
      else { return String(line) }
      let names = header.numbers.map { number in
        record.speakerNames[SessionSpeakerIdentity(source: header.source, number: number).id]
          ?? "Speaker \(number)"
      }
      let label = names.joined(separator: " + ") + (names.count > 1 ? " · overlap" : "")
      return "\(header.prefix)\(header.source) · \(label): \(header.text)"
    }.joined(separator: "\n")
    return record
  }

  private static func parse(_ line: Substring) -> Header? {
    guard line.first == "[", let stamp = line.range(of: "] "),
      let separator = line.range(of: ": ", range: stamp.upperBound..<line.endIndex)
    else { return nil }
    let heading = line[stamp.upperBound..<separator.lowerBound]
    guard let marker = heading.range(of: " · Speaker") else { return nil }
    let source = String(heading[..<marker.lowerBound])
    var suffix = heading[marker.upperBound...]
    if suffix.hasPrefix("s ") {
      suffix = suffix.dropFirst(2)
    } else if suffix.hasPrefix(" ") {
      suffix = suffix.dropFirst()
    } else {
      return nil
    }
    if let overlap = suffix.range(of: " · overlap") { suffix = suffix[..<overlap.lowerBound] }
    let components = suffix.components(separatedBy: " + ")
    let numbers = components.compactMap(Int.init)
    guard !numbers.isEmpty, numbers.count == components.count else { return nil }
    return Header(
      prefix: line[..<stamp.upperBound], source: source, numbers: numbers,
      text: line[separator.upperBound...])
  }
}
