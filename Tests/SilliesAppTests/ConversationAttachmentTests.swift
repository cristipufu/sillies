import AppKit
import Observation
import SilliesCore
import Synchronization
import Testing

@testable import SilliesApp

@Test @MainActor func conversationAcceptsHostGeometryWhileKeepingItsPerchDuringOwnWindowFocus()
  throws
{
  let pet = try chattingPet()
  defer { pet.closeAllPanels() }
  let initial = CGRect(x: 200, y: 200, width: 700, height: 300)
  let moved = initial.offsetBy(dx: 120, dy: 45)
  var first = placement(for: pet, frame: initial, running: false)
  _ = first.update(mode: .immediate)
  let previous = pet.surface
  var movement = placement(for: pet, frame: moved, running: false)
  _ = movement.update(mode: .immediate)
  #expect(pet.surface != previous)
  #expect(pet.attachedWindowID == 100)
  #expect(pet.holdsConversationPerch)
  #expect(pet.tween == nil)
  let last = pet.surface
  var ownWindow = placement(for: pet, frame: nil, running: false)
  _ = ownWindow.update(mode: .immediate)
  #expect(pet.surface == last)
}

@Test @MainActor func chatFollowsCompanionImmediatelyAndKeepsHostedContent() throws {
  let pet = try chattingPet()
  defer { pet.closeAllPanels() }
  let visible = CGRect(x: 0, y: 0, width: 1400, height: 1000)
  let surface = PerchSurface(
    window: CGRect(x: 200, y: 200, width: 800, height: 400),
    visibleFrame: visible, characterSize: 64)
  _ = pet.configureSurface(surface, window: nil, display: visible)
  let session = ChatWindowFixture.makeSession()
  let chat = ChatSessionWindowController(appearance: ThemeEnvironment())
  defer {
    chat.close()
    session.finish {}
  }
  chat.prepare(session, openSettings: { _ in })
  pet.onConversationAnchorChanged = { chat.follow($0) }
  let window = try #require(chat.window)
  let content = try #require(window.contentView)
  for step in 0..<120 {
    let point = CGPoint(x: 400 + Double(step), y: 700 + Double(step) / 4)
    pet.place(at: point)
    let expected = ConversationBubbleLayout(
      anchor: point, size: ChatWindowLayout.initialSize, visibleFrame: visible)
    #expect(window.frame.size == expected.frame.size)
    #expect(abs(window.frame.minX - expected.frame.minX) <= 0.5)
    #expect(abs(window.frame.minY - expected.frame.minY) <= 0.5)
    #expect(window.contentView === content)
  }
  let frame = window.frame
  chat.follow(
    .init(
      companionID: "another-mascot", position: .zero, visibleFrame: visible, edge: .top,
      windowLayer: 0))
  #expect(window.frame == frame)
  #expect(window.level == CompanionPanel.hudLevel(forWindowLayer: 0))
  chat.follow(
    .init(
      companionID: session.companionID, position: pet.position, visibleFrame: visible, edge: .top,
      windowLayer: NSWindow.Level.floating.rawValue))
  #expect(window.level == CompanionPanel.hudLevel(forWindowLayer: NSWindow.Level.floating.rawValue))
  #expect(!window.isVisible)
}

@Test @MainActor func openChatAndMascotTrackEveryHostWindowDragFrame() throws {
  let pet = try chattingPet()
  defer { pet.closeAllPanels() }
  let initial = CGRect(x: 200, y: 200, width: 700, height: 300)
  var first = placement(for: pet, frame: initial, running: true)
  _ = first.update(mode: .immediate)
  let session = ChatWindowFixture.makeSession()
  let chat = ChatSessionWindowController(appearance: ThemeEnvironment())
  defer {
    chat.close()
    session.finish {}
  }
  chat.prefersReducedMotion = { true }
  chat.show(session, openSettings: { _ in }, anchor: pet.conversationAnchor)
  pet.onConversationAnchorChanged = { chat.follow($0) }
  let window = try #require(chat.window)
  let initialPosition = pet.position
  let count = pet.placementCount
  for step in 1...120 {
    let dx = Double(step) / 2
    let dy = Double(step) / 4
    var movement = placement(for: pet, frame: initial.offsetBy(dx: dx, dy: dy), running: true)
    _ = movement.update(mode: .animated)
    #expect(abs(pet.position.x - initialPosition.x - dx) < 0.01)
    #expect(abs(pet.position.y - initialPosition.y - dy) < 0.01)
    let anchor = try #require(pet.conversationAnchor)
    let expected = ConversationBubbleLayout(
      anchor: anchor.position,
      size: ChatWindowLayout.initialSize, visibleFrame: anchor.visibleFrame
    ).frame
    #expect(abs(window.frame.minX - expected.minX) <= 0.5)
    #expect(abs(window.frame.minY - expected.minY) <= 0.5)
  }
  #expect(pet.placementCount - count == 120)
  #expect(pet.tween == nil)
}

@MainActor private func chattingPet() throws -> CompanionInstance {
  let definition = try #require(try CharacterCatalog().characters.first { $0.id == "mochi" })
  let pet = CompanionInstance(
    configuration: .init(definition: definition, size: 64, seed: 1),
    rig: CatRig(), transitions: TransitionLibrary(), appearance: ThemeEnvironment())
  pet.updateBinding(.active(target: nil, skill: .chat, startedAt: 0))
  return pet
}

@MainActor private func placement(for pet: CompanionInstance, frame: CGRect?, running: Bool)
  -> CompanionSurfacePlacement
{
  CompanionSurfacePlacement(
    companions: [pet],
    environment: .init(
      window: frame,
      windowID: frame == nil ? nil : 100, windowLayer: 0, followsWindows: true,
      isAwaitingWindow: false, isRunning: running, reducedMotion: true, isLowPower: false,
      characterSize: 64, geometryChange: nil), animations: AnimationLibrary())
}

@Test @MainActor func bubbleTailMovesNativelyWithoutPublishingDragSamplesToSwiftUI() throws {
  let presentation = ConversationBubblePresentation()
  let observations = Mutex(0)
  withObservationTracking {
    _ = presentation.tail
    _ = presentation.tailOffset
  } onChange: {
    observations.withLock { $0 += 1 }
  }
  let chrome = ConversationBubbleChromeView(theme: SilliesTheme())
  chrome.frame = CGRect(origin: .zero, size: ChatWindowLayout.initialSize)
  chrome.update(theme: SilliesTheme(), tail: .top, offset: presentation.tailOffset)
  presentation.onTailChanged = { [weak chrome] in chrome?.moveTail($0, to: $1) }
  for offset in stride(from: 80.0, to: 220, by: 1) {
    presentation.tailOffset = offset
    let outline = try #require(chrome.layer?.sublayers?.first as? CAShapeLayer)
    let path = try #require(outline.path)
    #expect(path.contains(CGPoint(x: offset, y: ConversationBubbleLayout.tailHeight / 2)))
    #expect(!path.contains(CGPoint(x: offset + 30, y: ConversationBubbleLayout.tailHeight / 2)))
  }
  #expect(observations.withLock { $0 } == 0)
}

@Test @MainActor func sidePerchChangesKeepTheChatComposerAndSelection() async throws {
  let session = ChatWindowFixture.makeSession()
  for _ in 0..<100 {
    if session.phase == .ready { break }
    try await Task.sleep(for: .milliseconds(5))
  }
  session.draft = "A draft worth keeping."
  let chat = ChatSessionWindowController(appearance: ThemeEnvironment())
  defer {
    chat.close()
    session.finish {}
  }
  chat.prepare(session, openSettings: { _ in })
  let window = try #require(chat.window)
  let content = try #require(window.contentView)
  content.layoutSubtreeIfNeeded()
  let composer = try #require(chatComposer(in: content))
  let selection = NSRange(location: 2, length: 5)
  composer.setSelectedRange(selection)
  let visible = CGRect(x: 0, y: 0, width: 1400, height: 1000)
  for edge in [PerchSurface.Edge.top, .left, .right, .top] {
    let point = CGPoint(x: edge == .left ? 220 : edge == .right ? 1180 : 700, y: 650)
    chat.follow(
      .init(
        companionID: session.companionID, position: point,
        visibleFrame: visible, edge: edge, windowLayer: 0))
    await Task.yield()
    content.layoutSubtreeIfNeeded()
    #expect(
      window.frame.size
        == ConversationBubbleLayout.windowSize(forBody: CGSize(width: 400, height: 548), edge: edge)
    )
    #expect(chatComposer(in: content) === composer)
    #expect(composer.selectedRange() == selection)
    #expect(session.draft == "A draft worth keeping.")
  }
}

@MainActor private func chatComposer(in view: NSView) -> ChatComposerTextView? {
  if let editor = view as? ChatComposerTextView { return editor }
  return view.subviews.lazy.compactMap { chatComposer(in: $0) }.first
}
