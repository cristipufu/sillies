import Foundation

/// Corrections are recording-scoped metadata and exact header edits. Spoken words stay untouched.
public enum SessionSpeakerNaming {
  public enum Failure: Error, Equatable { case ambiguousHeaders }
  public static func speakers(in record: SessionRecord) -> [SessionSpeakerIdentity] {
    let headers = descriptors(in: record)
    var suggestions: [String: Set<CallSpeakerName>] = [:]
    for header in headers {
      guard let name = header.automaticName else { continue }
      for identity in header.identities { suggestions[identity.id, default: []].insert(name) }
    }
    var seen: Set<String> = []
    return headers.flatMap(\.identities).filter { seen.insert($0.id).inserted }.map { identity in
      guard case .voice(let number) = identity.kind, let names = suggestions[identity.id],
        names.count == 1
      else { return identity }
      return .init(source: identity.source, number: number, suggestedName: names.first)
    }
  }

  public static func name(for identity: SessionSpeakerIdentity, in record: SessionRecord) -> String
  {
    if let manual = record.speakerNames[identity.id] { return manual }
    if record.speakerNameSuppressions.contains(identity.id) { return "" }
    return identity.suggestedName?.rawValue ?? ""
  }

  public static func rename(
    _ identity: SessionSpeakerIdentity, to name: String, in record: SessionRecord
  ) throws -> SessionRecord {
    var updated = record
    let value = cleanName(name)
    updated.speakerNames[identity.id] = value.isEmpty ? nil : value
    if value.isEmpty {
      updated.speakerNameSuppressions.insert(identity.id)
    } else {
      updated.speakerNameSuppressions.remove(identity.id)
    }
    updated.originalSpeakerTranscript = record.originalSpeakerTranscript ?? record.transcript
    updated.transcript = replacingHeaders(
      in: record, using: try headerReplacements(in: record, renamed: updated))
    return updated
  }

  private struct HeaderReplacement {
    let original: String
    let updated: String
  }

  private static func cleanName(_ name: String) -> String {
    let normalized = boundedNamePrefix(name).precomposedStringWithCanonicalMapping
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return String(boundedNamePrefix(normalized).prefix(CallSpeakerName.maximumCharacters))
  }

  private static func boundedNamePrefix(_ name: String) -> String {
    var scalars = String.UnicodeScalarView()
    var inspectedBytes = 0
    for scalar in name.unicodeScalars {
      inspectedBytes += scalar.utf8.count
      guard inspectedBytes <= CallSpeakerName.maximumUTF8Bytes else { break }
      if !CharacterSet.controlCharacters.contains(scalar), !CharacterSet.newlines.contains(scalar) {
        scalars.append(scalar)
      }
    }
    return String(scalars)
  }

  private static func headerReplacements(in record: SessionRecord, renamed updated: SessionRecord)
    throws -> [HeaderReplacement]
  {
    var replacements: [String: Set<String>] = [:]
    for header in descriptors(in: record) {
      replacements[
        header.renderedPrefix(
          names: record.speakerNames, suppressions: record.speakerNameSuppressions), default: []
      ]
      .insert(
        header.renderedPrefix(
          names: updated.speakerNames, suppressions: updated.speakerNameSuppressions))
    }
    guard
      !replacements.contains(where: { old, choices in
        choices.count > 1 && choices.contains(where: { $0 != old })
      })
    else {
      throw Failure.ambiguousHeaders
    }
    return replacements.compactMap { old, choices -> HeaderReplacement? in
      guard choices.count == 1, let new = choices.first, old != new else { return nil }
      return HeaderReplacement(original: old, updated: new)
    }.sorted { $0.original.count > $1.original.count }
  }

  private static func replacingHeaders(
    in record: SessionRecord, using replacements: [HeaderReplacement]
  ) -> String {
    record.transcript.split(separator: "\n", omittingEmptySubsequences: false)
      .map { line in
        guard let replacement = replacements.first(where: { line.hasPrefix($0.original) }) else {
          return String(line)
        }
        return replacement.updated + line.dropFirst(replacement.original.count)
      }.joined(separator: "\n")
  }

  private static func descriptors(in record: SessionRecord) -> [SessionSpeakerHeader] {
    if !record.transcriptSegments.isEmpty {
      return record.transcriptSegments.map(SessionSpeakerHeader.init(segment:))
    }
    return (record.originalSpeakerTranscript ?? record.transcript).split(separator: "\n")
      .compactMap(SessionSpeakerHeader.init(legacyLine:))
  }
}
