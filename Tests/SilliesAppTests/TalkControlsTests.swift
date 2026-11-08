import AppKit
import SilliesAudio
import SilliesChat
import SilliesCore
import SilliesReasoning
import SilliesTTS
import Synchronization
import Testing

@testable import SilliesApp

@Test @MainActor func talkTranscriptOpeningAndDismissalKeepCaptureAndFollowingTurnsAlive()
  async throws
{
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { removeTestFile(at: directory) }
  let skills = SkillCoordinator(vault: SessionVaultStore(directory: directory))
  let captures = TalkControlCaptureFactory()
  let session = makeTalkSession(captures: captures)
  let chat = ChatSessionWindowController(
    appearance: ThemeEnvironment(), reading: .init(size: .standard))
  defer { chat.close() }
  skills.makeChatSession = { _, _ in session }
  skills.onOpenChatSession = { chat.prepare($0, openSettings: { _ in }) }
  skills.onCloseChatSession = { chat.close($0) }
  skills.startConversation(.talk, for: "mochi", name: "Mochi")
  try await talkControlWait { session.phase == .listening }
  let device = try #require(captures.current.withLock { $0 })
  #expect(chat.window == nil)
  #expect(device.starts.withLock { $0 } == 1)

  for turn in 1...2 {
    if turn == 1 { skills.openSession(for: "mochi") } else { skills.openActiveSession() }
    let window = try #require(chat.window)
    window.contentView?.layoutSubtreeIfNeeded()
    #expect(!containsComposer(window.contentView))
    #expect(session.mode == .talk && session.isVoiceConversationActive)
    #expect(device.stops.withLock { $0 } == 0)
    #expect(!chat.windowShouldClose(window))
    #expect(chat.window == nil && !chat.dismissal.isMonitoring)
    #expect(session.mode == .talk && session.isVoiceConversationActive)

    device.words.withLock { $0 = "Turn \(turn) after reading the transcript." }
    session.finishListening()
    try await talkControlWait { session.messages.count == turn * 2 && session.phase == .listening }
    #expect(session.messages.last?.completion == .complete)
    #expect(device.stops.withLock { $0 } == 0)
  }
  skills.openSession(for: "mochi")
  session.onFinish?()
  try await talkControlWait { session.phase == .finished }
  #expect(chat.window == nil)
  #expect(device.stops.withLock { $0 } == 1)
  await skills.shutdown()
}

@Test @MainActor func talkBubbleFollowsTheMascotWithoutRemeasuringAndInheritsItsLevel() async throws
{
  let captures = TalkControlCaptureFactory()
  let session = makeTalkSession(captures: captures)
  await session.startTalk()
  try await talkControlWait { session.phase == .listening }
  defer { session.finish {} }
  let hud = CompanionHUDController(appearance: ThemeEnvironment())
  let companion = NSWindow(
    contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
  companion.isReleasedWhenClosed = false
  defer {
    hud.close()
    companion.close()
  }
  hud.companionWindow = companion
  hud.model.conversation = session
  let state = CompanionBindingState.active(target: nil, skill: .chat, startedAt: 0)
  let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
  func prepare(_ point: CGPoint) {
    hud.prepare(
      state: state,
      anchor: .init(companionPoint: point, characterSize: 84, visibleFrame: screen))
  }
  prepare(CGPoint(x: 100, y: 400))
  let panel = try #require(hud.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
  #expect(hud.bubbleLayout?.tail == .left)
  #expect(panel.frame.height < 100 && !panel.isVisible)
  #expect(panel.frame.minY >= 400 + CompanionSpeechBubbleLayout.contactClearance)
  #expect(panel.level == companion.level && !panel.ignoresMouseEvents)
  for step in 0..<120 { prepare(CGPoint(x: 100 + step, y: 400)) }
  #expect(hud.layoutMeasurements == 1)
  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    panel.appearance = NSAppearance(named: appearance)
    for (side, point) in [("left", CGPoint(x: 100, y: 400)), ("right", CGPoint(x: 1100, y: 880))] {
      prepare(point)
      #expect(screen.contains(panel.frame))
      #expect(hud.bubbleLayout?.tail == (side == "left" ? .left : .right))
      try saveHUDSnapshot(panel, name: "talk-bubble-\(name)-\(side)")
    }
  }
  companion.level = .floating
  prepare(CGPoint(x: 100, y: 400))
  #expect(panel.level == .floating && hud.layoutMeasurements == 1)
  let host = CGRect(x: 300, y: 100, width: 600, height: 300)
  for (x, tail) in [
    (host.minX + 8, CompanionSpeechBubbleLayout.Tail.left), (host.maxX - 8, .right),
  ] {
    hud.prepare(
      state: state,
      anchor: .init(
        companionPoint: CGPoint(x: x, y: host.maxY), characterSize: 84,
        visibleFrame: screen, windowFrame: host))
    #expect(hud.bubbleLayout?.tail == tail)
    #expect(panel.frame.minX >= host.minX && panel.frame.maxX <= host.maxX)
    #expect(hud.layoutMeasurements == 1)
  }
  session.showChat()
  #expect(!hud.showsHUD(for: state))
}

@Test(arguments: [CompanionSkillKind.record, .listen, .participate])
@MainActor func recordingControlsFollowTheMascotInASpeechBubble(skill: CompanionSkillKind)
  throws
{
  let hud = CompanionHUDController(appearance: ThemeEnvironment())
  let companion = NSWindow(
    contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
  companion.isReleasedWhenClosed = false
  companion.level = .floating
  defer {
    hud.close()
    companion.close()
  }
  hud.companionWindow = companion
  let audio = AudioSessionPresentation(kind: skill, sourceLabel: "Meeting + microphone")
  audio.phase = .capturing
  hud.model.audioSession = audio
  let host = CGRect(x: 300, y: 100, width: 600, height: 300)
  let screen = CGRect(x: 0, y: 0, width: 1200, height: 900)
  let target = WindowTargetCandidate(
    windowID: 12, processID: 34, appName: "Microsoft Teams", frame: host)
  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    for (side, x) in [("left", host.minX + 8), ("right", host.maxX - 8)] {
      let anchor = CompanionSpeechBubbleLayout.Anchor(
        companionPoint: CGPoint(x: x, y: host.maxY), characterSize: 84,
        visibleFrame: screen, windowFrame: host)
      hud.prepare(
        state: .active(
          target: target, skill: skill, startedAt: 0, statusDetail: "00:42 · Listening…",
          audioLevel: 0.6), anchor: anchor)
      let panel = try #require(hud.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
      panel.appearance = NSAppearance(named: appearance)
      #expect(hud.bubbleLayout?.tail == (side == "left" ? .left : .right))
      #expect(panel.frame.minY >= host.maxY + CompanionSpeechBubbleLayout.contactClearance)
      #expect(panel.frame.minX >= host.minX && panel.frame.maxX <= host.maxX)
      #expect(panel.frame.width < 400 && panel.frame.height < 100)
      #expect(!panel.isVisible && !panel.ignoresMouseEvents && !panel.canBecomeKey)
      #expect(panel.level == companion.level && hud.layoutMeasurements == 1)
      try saveHUDSnapshot(panel, name: "\(skill.rawValue)-bubble-\(name)-\(side)")

      let suggestion = MeetingSuggestion(
        question: "Who owns this?", evidence: "Unassigned.", elapsed: 42)
      #expect(
        hud.speechBubble.prepare(
          suggestion: suggestion,
          placement: .init(anchor: anchor, companionWindow: companion, controlsFrame: panel.frame)))
      let thought = try #require(
        hud.speechBubble.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
      #expect(!thought.frame.intersects(panel.frame))
      #expect(thought.level == companion.level && !thought.isVisible)
    }
  }
  hud.prepare(
    state: .completed(
      target: target, skill: skill, summary: "Saved locally", recordID: UUID(), expiresAt: 5),
    anchor: .init(
      companionPoint: CGPoint(x: 400, y: 400), characterSize: 84, visibleFrame: screen))
  #expect(hud.bubbleLayout != nil)
}

@MainActor private func saveHUDSnapshot(_ panel: NSWindow, name: String) throws {
  guard ProcessInfo.processInfo.environment["SILLIES_SKILL_UI_SNAPSHOTS"] == "1" else { return }
  let view = try #require(panel.contentView)
  view.layoutSubtreeIfNeeded()
  let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
  view.cacheDisplay(in: view.bounds, to: bitmap)
  let data = try #require(bitmap.representation(using: .png, properties: [:]))
  try data.write(
    to: FileManager.default.temporaryDirectory.appendingPathComponent("sillies-\(name).png"))
}

@Test @MainActor func talkExplicitChatSwitchStopsCaptureAndKeepsTheDraftAndWindow() async throws {
  let captures = TalkControlCaptureFactory()
  let session = makeTalkSession(captures: captures)
  let controller = ChatSessionWindowController(
    appearance: ThemeEnvironment(), reading: .init(size: .standard))
  defer {
    controller.close()
    session.finish {}
  }
  controller.prepare(session, openSettings: { _ in })
  let window = try #require(controller.window)
  let content = try #require(window.contentView)
  session.draft = "Keep this unsent thought."
  await session.startTalk()
  try await talkControlWait { session.phase == .listening }
  session.showChat()
  try await talkControlWait { session.phase == .ready }
  controller.prepare(session, openSettings: { _ in })
  content.layoutSubtreeIfNeeded()
  #expect(controller.window === window && window.contentView === content)
  #expect(session.draft == "Keep this unsent thought.")
  #expect(!session.isVoiceConversationActive && !window.isVisible)
  #expect(containsComposer(content))
  #expect(captures.current.withLock { $0?.stops.withLock { $0 } } == 1)
}

@MainActor private func containsComposer(_ view: NSView?) -> Bool {
  guard let view else { return false }
  return view is ChatComposerTextView || view.subviews.contains { containsComposer($0) }
}

@MainActor private func makeTalkSession(
  captures: TalkControlCaptureFactory, voice: any ChatSpeechOutput = TalkControlVoice()
) -> ChatSession {
  ChatSession(
    companionName: "Mochi",
    profile: .init(personality: "Warm and playful", languageIdentifier: "en"),
    services: .init(
      captureFactory: { _, update in captures.make(update: update) },
      loadLanguages: { .init(languages: [.init(id: "en-US", name: "English", isInstalled: true)]) },
      conversation: TalkControlReply(), speech: voice,
      deliver: { MainRunLoopDelivery.perform($0) }, history: .transient), companionID: "mochi")
}

@Test @MainActor func talkClarificationChoiceKeepsTheMicrophoneAndTypedDraft() async throws {
  let captures = TalkControlCaptureFactory()
  let session = makeTalkSession(captures: captures)
  let question = try #require(
    ChatClarification(question: "Which meeting?", choices: ["Planning", "Review"]))
  session.restore(
    .init(
      handle: .init(companionID: "mochi", generation: UUID()),
      checkpoint: .init(draft: "My typed thought"),
      page: .init(
        entries: [
          .init(
            sequence: 1,
            message: ChatMessage(role: .companion, text: question.question).asking(question),
            createdAt: Date())
        ], hasOlder: false, hasNewer: false)))
  await session.startTalk()
  try await talkControlWait { session.phase == .listening }
  let device = try #require(captures.current.withLock { $0 })
  #expect(session.canAnswerClarification)
  session.answerClarification(question.id, choice: "Planning")
  try await talkControlWait { session.phase == .listening && session.messages.count == 3 }
  #expect(session.isVoiceConversationActive && device.stops.withLock { $0 } == 0)
  #expect(session.history.checkpoint.draft == "My typed thought")
  #expect(session.messages[1].text == "Planning")
  await withCheckedContinuation { continuation in session.finish { continuation.resume() } }
  #expect(session.draft == "My typed thought")
}

private struct TalkControlReply: ConversationResponding {
  func reply(to context: ChatContext, progress: @escaping @Sendable (ChatProgress) -> Void)
    async throws -> ChatReply
  {
    .init(text: "Let's make your day a little easier.")
  }
}

private struct TalkControlVoice: ChatSpeechOutput {
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? { nil }
  func stop(id: UUID) async {}
  func pause(id: UUID) async {}
  func resume(id: UUID) async {}
}

private actor AttributedTalkVoice: ChatSpeechOutput {
  var attribution: ModelAttribution?
  func select(_ attribution: ModelAttribution?) { self.attribution = attribution }
  func modelAttribution() async -> ModelAttribution? { attribution }
  func speak(
    _ request: ChatSpeechRequest, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    receive(.attribution(attribution))
    return nil
  }
  func stop(id: UUID) async {}
  func pause(id: UUID) async {}
  func resume(id: UUID) async {}
}

@Test @MainActor func talkBubbleRemeasuresWhenVoiceCreditArrivesAndClears() async throws {
  let captures = TalkControlCaptureFactory()
  let voice = AttributedTalkVoice()
  let session = makeTalkSession(captures: captures, voice: voice)
  await session.startTalk()
  try await talkControlWait { session.phase == .listening }
  let hud = CompanionHUDController(appearance: ThemeEnvironment())
  defer {
    hud.close()
    session.finish {}
  }
  hud.model.conversation = session
  let state = CompanionBindingState.active(target: nil, skill: .chat, startedAt: 0)
  let anchor = CompanionSpeechBubbleLayout.Anchor(
    companionPoint: CGPoint(x: 300, y: 400), characterSize: 84,
    visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900))
  hud.prepare(state: state, anchor: anchor)
  let initial = try #require(hud.currentPanelSize)
  let device = try #require(captures.current.withLock { $0 })
  let credit = ModelAttribution(
    text: "Voice by Underdog Woof", url: try #require(URL(string: "https://underdog.ai")))
  for (turn, selected) in [Optional(credit), nil].enumerated() {
    await voice.select(selected)
    device.words.withLock { $0 = "Hello again" }
    session.finishListening()
    try await talkControlWait {
      session.messages.count == (turn + 1) * 2 && session.phase == .listening
    }
    #expect(session.voiceAttribution == selected)
    hud.prepare(state: state, anchor: anchor)
    let size = try #require(hud.currentPanelSize)
    #expect(selected == nil ? size == initial : size.height > initial.height)
    #expect(hud.layoutMeasurements == turn + 2)
    #expect(!hud.isVisible)
  }
}

private final class TalkControlCaptureFactory: Sendable {
  let current = Mutex<TalkControlCapture?>(nil)
  func make(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) -> TalkControlCapture {
    let capture = TalkControlCapture(update: update)
    current.withLock { $0 = capture }
    return capture
  }
}

private final class TalkControlCapture: ConversationCapture, Sendable {
  let starts = Mutex(0)
  let stops = Mutex(0)
  let words = Mutex("")
  let update: @Sendable (AudioCaptureUpdate) -> Void
  init(update: @escaping @Sendable (AudioCaptureUpdate) -> Void) { self.update = update }
  func start() {
    starts.withLock { $0 += 1 }
    update(.capturing("Listening"))
  }
  func finishTurn(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    let text = words.withLock { value in
      let text = value
      value = ""
      return text
    }
    completion(.init(transcript: text, recordingURL: nil, duration: 1, failure: nil))
  }
  func finish(completion: @escaping @Sendable (AudioCaptureResult) -> Void) {
    stops.withLock { $0 += 1 }
    finishTurn(completion: completion)
  }
}

@MainActor private func talkControlWait(_ condition: () -> Bool) async throws {
  let deadline = ContinuousClock.now.advanced(by: .seconds(2))
  while !condition() {
    if ContinuousClock.now >= deadline { throw TalkControlTimeout() }
    try await Task.sleep(for: .milliseconds(5))
  }
}
private struct TalkControlTimeout: Error {}
