import ApplicationServices
import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech
import Synchronization
import Testing

@testable import SilliesApp

@Test func callSpeakerParsersRequireKnownSignalsAndRejectAmbiguity() async throws {
  var zoom = ZoomCallSpeakerProvider()
  let unrelated = zoom.zoomTile("Alice, video off")
  #expect(!unrelated)
  let valid = zoom.zoomTile("Smith, Alice, Computer audio unmuted, Video off, Active speaker")
  #expect(valid)
  #expect(zoom.evidence.speaking.map(\.rawValue) == ["Smith, Alice"])
  let local = zoom.zoomTile("Me (me), Computer audio unmuted, Video off")
  #expect(local)
  #expect(zoom.evidence.localParticipant?.rawValue == "Me")
  let combined = zoom.zoomTile("Me (Host, me), Computer audio unmuted, Video off, Active speaker")
  #expect(combined)
  #expect(zoom.evidence.localParticipant?.rawValue == "Me")
  var pair = ZoomCallSpeakerProvider()
  pair.zoomRoster(rows: ["Me (Host, me)", "Alice"], declaredCount: 3)
  #expect(pair.evidence.roster == .partial)
  pair.zoomRoster(rows: ["Me (Host, me)", "Alice"], declaredCount: 2)
  #expect(pair.evidence.roster == .complete)
  #expect(pair.evidence.localParticipant?.rawValue == "Me")
  #expect(pair.evidence.participants.map(\.rawValue) == ["Me", "Alice"])
  var teams = TeamsCallSpeakerProvider()
  teams.teamsSpeakingLabel("Alice is speaking about the launch")
  #expect(teams.evidence.speaking.isEmpty)
  teams.teamsSpeakingLabel("Alice is speaking")
  teams.teamsSpeakingLabel("Active speaker: Bob")
  teams.teamsSpeakingLabel("Me (You), speaking")
  #expect(teams.evidence.speaking.map(\.rawValue) == ["Alice", "Bob"])
  #expect(teams.evidence.localParticipant?.rawValue == "Me")
  var meet = MeetCallSpeakerProvider()
  meet.meetSpeakingTile(texts: ["Alice", "Alice"])
  #expect(meet.evidence.speaking.map(\.rawValue) == ["Alice"])
  meet.meetSpeakingTile(texts: ["Alice", "Turn on microphone"])
  #expect(meet.evidence.isAmbiguous)
  #expect(CallSpeakerTreeRead.excludes(role: "AXTextField"))
  #expect(CallSpeakerTreeRead.excludes(role: "AXTextArea"))
  #expect(CallSpeakerTreeRead.excludes(identifier: "meeting-chat-panel"))
  #expect(CallSpeakerProviders.make("com.example.editor") == nil)
}

@Test @MainActor func callSpeakerMonitorRejectsCancelledReadsAndStopsExactlyOnce() async throws {
  let reader = ControlledCallReader()
  let capture = CallObservationCapture()
  var pointerDown = false
  let monitor = CallSpeakerMonitor(
    reader: reader,
    environment: .init(
      isPointerDown: { pointerDown }, primaryScreenTop: { 1000 }))
  let target = WindowTargetCandidate(
    windowID: 7, processID: 42, appName: "Zoom", bundleIdentifier: "us.zoom.xos",
    frame: CGRect(x: 10, y: 10, width: 500, height: 400))
  func context(_ now: Double) -> SkillTickContext {
    .init(
      now: now, startedAt: 0, currentDetail: "", currentAudioLevel: 0, target: target,
      snapshot: .init(frame: target.frame, title: nil, ownerPID: 42), frontmostPID: 42)
  }
  monitor.tick(context(0), capture: capture)
  monitor.tick(context(0.7), capture: capture)
  var starts = reader.starts.makeAsyncIterator()
  _ = await starts.next()
  pointerDown = true
  monitor.tick(context(0.8), capture: capture)
  #expect(capture.observations.map(\.availability) == [.unavailable])
  await reader.release()
  pointerDown = false
  monitor.tick(context(1.5), capture: capture)
  _ = await starts.next()
  await reader.release()
  try await waitForCallSpeakerCondition { capture.observations.count == 2 }
  #expect(capture.observations.map(\.availability) == [.unavailable, .available])
  monitor.suspend()
  monitor.tick(context(2), capture: capture)
  #expect(await reader.readCount == 2)
  monitor.stop()
  monitor.stop()
  try await waitForCallSpeakerCondition { await reader.stopCount == 1 }
  monitor.tick(context(10), capture: capture)
  #expect(await reader.readCount == 2)
}

@Test func callSpeakerProvidersOwnScopesAndRequestOnlyRecognizedContent() async throws {
  var rosterReads = 0
  var tileReads = 0
  var node = CallSpeakerNode(
    role: "AXGroup", description: "Alice is speaking", classes: ["v5h6Xc"],
    readRoster: {
      rosterReads += 1
      return .init(rows: ["Me (me)", "Alice"], declaredCount: 2)
    },
    readSpeakingTile: { _ in
      tileReads += 1
      return ["Alice"]
    })
  var teams = TeamsCallSpeakerProvider()
  let teamsTraversal = teams.inspect(node)
  #expect(teamsTraversal == .children)
  #expect(teams.evidence.speaking.map(\.rawValue) == ["Alice"])
  #expect(rosterReads == 0 && tileReads == 0)
  var meet = MeetCallSpeakerProvider()
  let outsidePage = meet.inspect(node)
  #expect(outsidePage == .children)
  #expect(tileReads == 0)
  node.scope = .verifiedCallPage
  let insidePage = meet.inspect(node)
  #expect(insidePage == .skip)
  #expect(tileReads == 1 && rosterReads == 0)
  #expect(meet.evidence.speaking.map(\.rawValue) == ["Alice"])
  let unrelated = meet.inspect(.init(role: "AXWebArea", url: URL(string: "https://example.com/")))
  let verified = meet.inspect(
    .init(role: "AXWebArea", url: URL(string: "https://meet.google.com/abc-defg-hij")))
  #expect(unrelated == .skip && verified == .callPage)
  var zoom = ZoomCallSpeakerProvider()
  let skipped = zoom.inspect(node)
  #expect(skipped == .children)
  var roster = CallSpeakerNode(role: "AXOutline", description: "Participants list")
  roster.readRoster = node.readRoster
  let rosterTraversal = zoom.inspect(roster)
  #expect(rosterTraversal == .skip)
  #expect(rosterReads == 1 && tileReads == 1)
  #expect(zoom.evidence.roster == .complete)
  #expect(zoom.evidence.localParticipant?.rawValue == "Me")
  var oversizedNode = node
  oversizedNode.classes = Array(repeating: "v5h6Xc", count: 1_000)
  var invalidMeet = MeetCallSpeakerProvider()
  let rejected = invalidMeet.inspect(oversizedNode)
  #expect(rejected == .skip)
  #expect(invalidMeet.evidence.isAmbiguous)
  #expect(tileReads == 1)
}

@Test func callSpeakerNativeReaderRejectsUnrelatedApplicationsAndReadsAfterStop() async {
  let reader = CallWindowSpeakerReader(
    makeProvider: CallSpeakerProviders.make,
    accessibility: CallAccessibilityRegistry(prepare: { _ in .init(restore: { true }) }))
  let request = CallSpeakerReadRequest(
    target: .init(
      windowID: 1, processID: 1,
      appName: "Editor", bundleIdentifier: "com.example.editor", frame: .zero),
    primaryScreenTop: 1000)
  #expect(await reader.read(request).availability == .unsupported)
  await reader.stop()
  #expect(await reader.read(request).availability == .unsupported)
}

@Test func callSpeakerAccessibilityLeasesRestoreOnlyAfterTheFinalRecording() async {
  let preparations = Mutex<[Int32]>([])
  let restorations = Mutex<[Int32]>([])
  let registry = CallAccessibilityRegistry(prepare: { pid in
    preparations.withLock { $0.append(pid) }
    return .init(restore: {
      restorations.withLock { $0.append(pid) }
      return true
    })
  })
  let first = await registry.acquire(processID: 42)
  let second = await registry.acquire(processID: 42)
  let other = await registry.acquire(processID: 43)
  #expect(preparations.withLock { $0 } == [42, 43])
  await registry.release(first)
  await registry.release(first)
  #expect(restorations.withLock { $0.isEmpty })
  await registry.release(other)
  await registry.release(second)
  await registry.release(second)
  #expect(restorations.withLock { $0 } == [43, 42])
}

@Test @MainActor func callSpeakerAmbiguousCorrectionsKeepTheSavedTranscriptAndReportFailure()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let vault = SessionVaultStore(directory: directory)
  vault.suspendBackgroundProcessing()
  var record = SessionRecord(
    kind: .listen,
    origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Zoom")))
  let name = try #require(CallSpeakerName(rawValue: "Alice"))
  record.transcriptSegments = [
    .init(
      sequence: 0, source: "Meeting", start: 1, end: 1.2, text: "First", speaker: .identified(1),
      automaticSpeakerName: name),
    .init(
      sequence: 1, source: "Meeting", start: 1.3, end: 1.4, text: "Second", speaker: .identified(2),
      automaticSpeakerName: name),
  ]
  record.transcript = record.transcriptSegments.map(\.transcriptLine).joined(separator: "\n")
  vault.add(record)
  await vault.flush()
  let model = SessionVaultModel(vault: vault, presentation: .init())
  let speaker = try #require(SessionSpeakerNaming.speakers(in: record).first)
  model.rename(speaker, to: "Dana", in: record)
  try await waitForCallSpeakerCondition { model.feedback != nil }
  #expect(
    model.feedback
      == String(
        localized:
          "These speaker labels are ambiguous. Edit the transcript directly to correct them."))
  let saved = try #require(try await vault.record(id: record.id))
  #expect(saved.transcript == record.transcript)
  #expect(saved.speakerNames.isEmpty)
  #expect(saved.speakerNameSuppressions.isEmpty)
  model.stop()
}

@Test func callSpeakerWindowBindingChecksNativeIdentifiersAndFallbackGeometry() throws {
  var point = CGPoint(x: 10, y: 590)
  var size = CGSize(width: 500, height: 400)
  let position = try #require(AXValueCreate(.cgPoint, &point))
  let dimensions = try #require(AXValueCreate(.cgSize, &size))
  let request = CallSpeakerReadRequest(
    target: .init(
      windowID: 7, processID: 42, appName: "Zoom",
      windowTitle: "Call", frame: CGRect(x: 10, y: 10, width: 500, height: 400)),
    primaryScreenTop: 1000)
  var values: [CallSpeakerAX.Attribute: AnyObject] = [
    .role: "AXWindow" as NSString, .position: position, .size: dimensions,
    .title: "Call" as NSString,
  ]
  #expect(CallSpeakerAX.matches(values: values, request: request))
  for number: NSNumber in [
    -1, 7.5, NSNumber(value: UInt64.max), NSNumber(value: Double.nan),
    NSNumber(value: Double.infinity), NSDecimalNumber.notANumber, 8,
  ] {
    values[.number] = number
    #expect(!CallSpeakerAX.matches(values: values, request: request))
  }
  values[.number] = 7 as NSNumber
  #expect(CallSpeakerAX.matches(values: values, request: request))
  values[.number] = nil
  values[.title] = "Another call" as NSString
  #expect(!CallSpeakerAX.matches(values: values, request: request))
  values[.title] = "Call" as NSString
  values[.minimized] = true as NSNumber
  #expect(!CallSpeakerAX.matches(values: values, request: request))
  values[.minimized] = nil
  values[.role] = "AXApplication" as NSString
  #expect(!CallSpeakerAX.matches(values: values, request: request))
  values[.role] = "AXWindow" as NSString
  point.x = .nan
  values[.position] = try #require(AXValueCreate(.cgPoint, &point))
  #expect(!CallSpeakerAX.matches(values: values, request: request))
  values[.position] = NSNull()
  #expect(!CallSpeakerAX.matches(values: values, request: request))
  values[.position] = position
  values[.size] = "not geometry" as NSString
  #expect(!CallSpeakerAX.matches(values: values, request: request))
}

private actor ControlledCallReader: CallSpeakerReading {
  nonisolated let starts: AsyncStream<Void>
  private let started: AsyncStream<Void>.Continuation
  private var pending: CheckedContinuation<CallSpeakerObservation, Never>?
  private var request: CallSpeakerReadRequest?
  private(set) var readCount = 0
  private(set) var stopCount = 0
  init() { (starts, started) = AsyncStream<Void>.makeStream() }
  func read(_ request: CallSpeakerReadRequest) async -> CallSpeakerObservation {
    readCount += 1
    self.request = request
    return await withCheckedContinuation {
      pending = $0
      started.yield(())
    }
  }
  func release() {
    guard let request else { return }
    pending?.resume(
      returning: .init(
        source: .init(processID: request.target.processID, windowID: request.target.windowID),
        capturedAt: 1, availability: .available))
    pending = nil
  }
  func stop() {
    stopCount += 1
    release()
  }
}

private final class CallObservationCapture: SessionAudioCapture {
  private let readings = Mutex<[CallSpeakerObservation]>([])
  var observations: [CallSpeakerObservation] { readings.withLock { $0 } }
  func start() {}
  func pause() {}
  func resume() {}
  func changeLanguage(_ language: SpeechLanguage) {}
  func observeCallSpeakers(_ observation: CallSpeakerObservation) {
    readings.withLock { $0.append(observation) }
  }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    completion(.init(transcript: "", recordingURL: nil, duration: 0, failure: nil))
  }
}

@MainActor private func waitForCallSpeakerCondition(_ condition: () async -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !(await condition()), ContinuousClock.now < deadline {
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await condition())
}

@Test func callSpeakerStructuredNamesKeepPunctuationAndRequireExplicitLocalRoles() {
  let remote = CallParticipantLabel("Doe, Jane (Design, Europe)")
  #expect(remote?.name.rawValue == "Doe, Jane (Design, Europe)")
  #expect(remote?.identity == .remote)
  let local = CallParticipantLabel("Jane (Host, me)")
  #expect(local?.name.rawValue == "Jane")
  #expect(local?.identity == .local)
  let punctuation = CallParticipantLabel("Jane（Host、me）")
  #expect(punctuation?.name.rawValue == "Jane" && punctuation?.identity == .local)
  let unrecognized = CallParticipantLabel("Jane (unverified, me)")
  #expect(unrecognized?.name.rawValue == "Jane (unverified, me)")
  #expect(unrecognized?.identity == .remote)
  var zoom = ZoomCallSpeakerProvider()
  let tileAccepted = zoom.zoomTile(
    "Doe, Jane (Design, Europe), Computer audio unmuted, Active speaker")
  #expect(tileAccepted)
  #expect(zoom.evidence.speaking.map(\.rawValue) == ["Doe, Jane (Design, Europe)"])
}

@Test func callSpeakerStructuredMetadataRejectsConflictsAndMalformedFields() {
  var zoom = ZoomCallSpeakerProvider()
  let tileAccepted = zoom.zoomTile("Alice, Computer audio muted, Active speaker")
  #expect(tileAccepted)
  #expect(zoom.evidence.isAmbiguous && zoom.evidence.speaking.isEmpty)
  for label in [
    "Alice, , Computer audio unmuted", "Alice (guest, Computer audio unmuted",
    "Alice), Computer audio unmuted", "Alice, Computer audio muted, Computer audio unmuted",
  ] {
    #expect(ZoomParticipantMetadata(label) == nil)
  }
  var teams = TeamsCallSpeakerProvider()
  let result = teams.inspect(
    .init(role: "AXRow", description: "Alice is speaking", title: "Bob is talking"))
  #expect(result == .skip && teams.evidence.isAmbiguous && teams.evidence.speaking.isEmpty)
}

@Test func callSpeakerTeamsAcceptsCompleteStatusAndUnicodeWhitespace() {
  let spaced = TeamsSpeakingMetadata.participant(in: " Alice\u{00a0}is\t speaking ")
  #expect(spaced?.name.rawValue == "Alice")
  let comma = TeamsSpeakingMetadata.participant(in: "Doe, Jane,speaking")
  #expect(comma?.name.rawValue == "Doe, Jane")
  #expect(TeamsSpeakingMetadata.participant(in: "Alice says: Bob is speaking") == nil)
  #expect(TeamsSpeakingMetadata.participant(in: "Alice is speaking about the launch") == nil)
  #expect(TeamsSpeakingMetadata.participant(in: "Active speaker: ") == nil)
}

@Test func callSpeakerMeetIdentityRejectsInterfaceTextAndKeepsUnicodeNames() {
  for text in ["12:30 PM", "9.05am", "abc-defg-hij", "Alice says in chat: hello", "42"] {
    #expect(MeetParticipantMetadata(texts: [text]) == nil)
  }
  let unicode = MeetParticipantMetadata(texts: ["Ștefan 李", "Ștefan 李"])
  #expect(unicode?.participant.name.rawValue == "Ștefan 李")
  let local = MeetParticipantMetadata(texts: ["Alice", "Alice (you)"])
  #expect(local?.participant.identity == .local)
  #expect(MeetParticipantMetadata(texts: ["Alice", "Bob"]) == nil)
}

@Test func callSpeakerNewParsersRejectOversizedMetadataBeforeNormalization() {
  let oversized = String(repeating: "\u{034f}", count: CallSpeakerText.maximumMetadataBytes)
  #expect(CallMetadataFields(oversized) == nil)
  #expect(CallParticipantLabel(oversized) == nil)
  #expect(TeamsSpeakingMetadata.participant(in: oversized) == nil)
  #expect(MeetParticipantMetadata(texts: [oversized]) == nil)
}
