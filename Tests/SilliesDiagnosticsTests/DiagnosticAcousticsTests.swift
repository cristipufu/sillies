import Foundation
import Testing

@testable import SilliesDiagnostics

@Test func diagnosticsBoundAcousticNumbersAndRejectNonFiniteValues() throws {
  var acoustics = DiagnosticAcoustics(boundary: .onset, utterance: UUID())
  acoustics.samples = Int.max
  acoustics.referenceSamples = Int.max
  acoustics.clippedSamples = -1
  acoustics.referenceDecibels = .nan
  acoustics.microphoneDecibels = .infinity
  acoustics.cleanedDecibels = -200
  acoustics.referenceAgeMilliseconds = .infinity
  acoustics.echoDelayMilliseconds = -1
  acoustics.echoReturnLossDecibels = .nan
  acoustics.echoReductionDecibels = 500
  var event = DiagnosticEvent(.capture, .acousticAssessment)
  event.acoustics = acoustics
  let bounded = try #require(event.validated().acoustics)
  #expect(bounded.samples == 16_000 && bounded.referenceSamples == 16_000)
  #expect(bounded.clippedSamples == 0 && bounded.cleanedDecibels == -120)
  #expect(bounded.referenceDecibels == nil && bounded.microphoneDecibels == nil)
  #expect(bounded.referenceAgeMilliseconds == nil && bounded.echoReturnLossDecibels == nil)
  #expect(bounded.echoDelayMilliseconds == 0 && bounded.echoReductionDecibels == 120)
  _ = try JSONEncoder().encode(event.validated())
}

@Test func diagnosticsAcousticExportDiscardsInjectedContentAndRetainsCorrelation() async throws {
  let fixture = try DiagnosticFixture()
  defer { fixture.remove() }
  let operation = UUID()
  let session = UUID()
  var event = DiagnosticEvent(.capture, .acousticAssessment, operation: operation)
  event.relatedOperation = session
  event.acoustics = .init(boundary: .endpoint, utterance: UUID())
  let record = DiagnosticRecord(event: event, launch: fixture.launch, sequence: 1)
  let data = try DiagnosticRecord.encoder().encode(record)
  var json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
  var payload = try #require(json["event"] as? [String: Any])
  var acoustics = try #require(payload["acoustics"] as? [String: Any])
  acoustics["audio"] = "private microphone samples"
  acoustics["transcript"] = "private recognized words"
  acoustics["path"] = "/Users/private/audio.wav"
  payload["acoustics"] = acoustics
  json["event"] = payload
  try FileManager.default.createDirectory(at: fixture.archive, withIntermediateDirectories: true)
  var injected = try JSONSerialization.data(withJSONObject: json)
  injected.append(0x0A)
  try injected.write(to: fixture.archive.appendingPathComponent("events-0.jsonl"))
  let recorder = DiagnosticRecorder(
    directory: fixture.archive, enabled: true, limits: fixture.limits)
  try await recorder.start()
  try await recorder.export(to: fixture.export, environment: .init())
  let report = try fixture.report()
  #expect(report.events.first?.event.operation == operation)
  #expect(report.events.first?.event.relatedOperation == session)
  #expect(report.events.first?.event.acoustics?.boundary == .endpoint)
  #expect(try !String(contentsOf: fixture.export, encoding: .utf8).contains("private"))
  await recorder.shutdown()
}
