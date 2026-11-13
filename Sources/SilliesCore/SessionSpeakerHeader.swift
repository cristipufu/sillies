import Foundation

/// A descriptor changes headers by exact prefix; the current spoken text is never reconstructed.
struct SessionSpeakerHeader {
  let prefix: String
  let source: String
  let numbers: [Int]
  let automaticName: CallSpeakerName?
  var identities: [SessionSpeakerIdentity] {
    if !numbers.isEmpty { return numbers.map { .init(source: source, number: $0) } }
    return automaticName.map { [.init(source: source, participant: $0)] } ?? []
  }
  init(segment: TranscriptSegment) {
    prefix = "[\(SessionRecord.formatDuration(segment.start))] "
    source = segment.source
    automaticName = segment.automaticSpeakerName
    switch segment.speaker {
    case .identified(let number): numbers = [number]
    case .overlapping(let values): numbers = values
    case .unknown, nil: numbers = []
    }
  }
  init?(legacyLine line: Substring) {
    guard line.first == "[", let stamp = line.range(of: "] "),
      let separator = line.range(of: ": ", range: stamp.upperBound..<line.endIndex)
    else { return nil }
    let heading = line[stamp.upperBound..<separator.lowerBound]
    guard let marker = heading.range(of: " · Speaker") else { return nil }
    source = String(heading[..<marker.lowerBound])
    var suffix = heading[marker.upperBound...]
    if suffix.hasPrefix("s ") {
      suffix = suffix.dropFirst(2)
    } else if suffix.hasPrefix(" ") {
      suffix = suffix.dropFirst()
    } else {
      return nil
    }
    if let overlap = suffix.range(of: " · overlap") { suffix = suffix[..<overlap.lowerBound] }
    let parts = suffix.components(separatedBy: " + ")
    numbers = parts.compactMap(Int.init)
    guard !numbers.isEmpty, numbers.count == parts.count else { return nil }
    prefix = String(line[..<stamp.upperBound])
    automaticName = nil
  }
  func renderedPrefix(names: [String: String], suppressions: Set<String>) -> String {
    let manualVoices = numbers.map {
      names[SessionSpeakerIdentity(source: source, number: $0).id].flatMap(
        CallSpeakerName.init(rawValue:))
    }
    let label: String?
    if manualVoices.contains(where: { $0 != nil }) {
      let parts = zip(numbers, manualVoices).map { number, manual in
        manual?.transcriptLabel ?? "Speaker \(number)"
      }
      label = parts.joined(separator: " + ") + (numbers.count > 1 ? " · overlap" : "")
    } else if let automaticName,
      !identities.contains(where: { suppressions.contains($0.id) }),
      !suppressions.contains(SessionSpeakerIdentity(source: source, participant: automaticName).id)
    {
      let identity = SessionSpeakerIdentity(source: source, participant: automaticName)
      label =
        names[identity.id].flatMap(CallSpeakerName.init(rawValue:))?.transcriptLabel
        ?? automaticName.transcriptLabel
    } else {
      switch numbers.count {
      case 0: label = nil
      case 1: label = numbers.first.map { "Speaker \($0)" }
      default: label = "Speakers \(numbers.map(String.init).joined(separator: " + ")) · overlap"
      }
    }
    return prefix + source + (label.map { " · " + $0 } ?? "") + ": "
  }
}
