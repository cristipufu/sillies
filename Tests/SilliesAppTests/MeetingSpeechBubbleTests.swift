import AppKit
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func suggestionBubbleReplacesOneIdeaAndHidesWithHUD() throws {
  _ = NSApplication.shared
  let window = NSWindow(
    contentRect: CGRect(x: 100, y: 100, width: 600, height: 400), styleMask: [.titled],
    backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let session = AudioSessionPresentation(kind: .participate, sourceLabel: "Meeting + microphone")
  session.phase = .capturing
  session.suggestions = [
    MeetingSuggestion(
      question: "Who will follow up with the customer?", evidence: "The owner is still undecided.",
      elapsed: 60)
  ]
  let hud = CompanionHUDController()
  defer { hud.close() }
  hud.companionWindowNumber = window.windowNumber
  hud.model.audioSession = session
  let target = WindowTargetCandidate(
    windowID: UInt32(window.windowNumber), processID: ProcessInfo.processInfo.processIdentifier,
    appName: "Meeting", frame: window.frame)
  let state = CompanionBindingState.active(target: target, skill: .participate, startedAt: 0)
  let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
  func update(_ point: CGPoint) {
    hud.update(state: state, companionPoint: point, characterSize: 64, visibleFrame: screen)
  }
  update(CGPoint(x: 500, y: 600))
  let id = try #require(hud.speechBubble.windowNumber)
  let bubble = try #require(NSApp.window(withWindowNumber: id))
  #expect(hud.speechBubble.isVisible)
  #expect(bubble.ignoresMouseEvents && !bubble.canBecomeKey && !bubble.canBecomeMain)
  #expect(WindowTrackingExclusions.shared.contains(UInt32(id)))
  #expect(bubble.level.rawValue > CompanionPanel.normalOverlayLevel.rawValue)
  #expect(bubble.level.rawValue < NSWindow.Level.floating.rawValue)
  #expect(bubble.frame.height < 150)
  for step in 0..<120 { update(CGPoint(x: 500 + step, y: 600)) }
  #expect(hud.speechBubble.contentUpdates == 1)
  #expect(hud.speechBubble.layoutMeasurements == 1)
  session.suggestions.append(
    MeetingSuggestion(
      question: "What deadline should we agree on?", evidence: "No date has been set.", elapsed: 120
    ))
  update(CGPoint(x: 619, y: 600))
  #expect(hud.speechBubble.windowNumber == id)
  #expect(hud.speechBubble.contentUpdates == 2)
  #expect(hud.speechBubble.layoutMeasurements == 2)
  hud.hide()
  #expect(!hud.speechBubble.isVisible)
  update(CGPoint(x: 619, y: 600))
  #expect(hud.speechBubble.isVisible)
  session.phase = .paused
  update(CGPoint(x: 619, y: 600))
  #expect(!hud.speechBubble.isVisible)
  session.phase = .capturing
  session.suggestionsEnabled = false
  update(CGPoint(x: 619, y: 600))
  #expect(!hud.speechBubble.isVisible)
  hud.close()
  #expect(!WindowTrackingExclusions.shared.contains(UInt32(id)))
}

@Test @MainActor func listenNeverPresentsMeetingSuggestions() {
  let session = AudioSessionPresentation(kind: .listen, sourceLabel: "Meeting + microphone")
  session.phase = .capturing
  session.suggestionsEnabled = true
  session.suggestions = [
    MeetingSuggestion(question: "A question?", evidence: "Some evidence.", elapsed: 1)
  ]
  #expect(session.currentBubbleSuggestion == nil)
}

@Test @MainActor func suggestionBubbleWrapsItsTextAndStaysAboveWalkingCompanions() throws {
  _ = NSApplication.shared
  let bubble = MeetingSpeechBubbleController()
  defer { bubble.close() }
  let anchor = SuggestionBubbleLayout.Anchor(
    companionPoint: CGPoint(x: 300, y: 500), characterSize: 64,
    visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900))
  bubble.update(
    suggestion: MeetingSuggestion(question: "Who owns this?", evidence: "Unassigned.", elapsed: 60),
    placement: .init(anchor: anchor, windowLayer: 0))
  let panel = try #require(bubble.windowNumber.flatMap { NSApp.window(withWindowNumber: $0) })
  let compactSize = panel.frame.size
  #expect(compactSize.width < 250 && compactSize.height < 110)
  bubble.update(
    suggestion: MeetingSuggestion(
      question:
        "Who will take ownership of the customer follow-up, confirm the review deadline, and coordinate the proposal with the rest of the team before Friday?",
      evidence: "Unassigned.", elapsed: 120), placement: .init(anchor: anchor, windowLayer: 0))
  #expect(panel.frame.height > compactSize.height)
  #expect(panel.frame.width <= 300)
  #expect(panel.level.rawValue > CompanionPanel.normalOverlayLevel.rawValue)
  bubble.update(
    suggestion: MeetingSuggestion(
      question: "Who owns this?", evidence: "Unassigned.", elapsed: 180),
    placement: .init(anchor: anchor, windowLayer: NSWindow.Level.floating.rawValue))
  #expect(panel.level.rawValue > CompanionPanel.floatingOverlayLevel.rawValue)
  #expect(panel.level.rawValue < CompanionPanel.contentWindowLevel.rawValue)
}

@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_UI_PREVIEW"] == "1"))
@MainActor func renderMeetingSpeechBubblePreview() throws {
  let suggestion = MeetingSuggestion(
    question: "Who’s taking ownership of the customer follow-up, and when should we check back?",
    evidence: "The owner is still undecided.", elapsed: 30)
  for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
    let host = NSHostingController(rootView: MeetingSpeechBubbleView(suggestion: suggestion))
    host.sizingOptions = []
    let size = host.sizeThatFits(in: CGSize(width: 300, height: CGFloat.greatestFiniteMagnitude))
    let layout = SuggestionBubbleLayout(
      anchor: .init(
        companionPoint: CGPoint(x: 200, y: 400), characterSize: 70,
        visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900)), size: size)
    let view = MeetingSpeechBubbleBackground(
      frame: CGRect(origin: .zero, size: size))
    view.appearance = NSAppearance(named: appearance)
    host.view.frame = view.bounds
    view.addSubview(host.view)
    view.update(layout)
    view.layoutSubtreeIfNeeded()
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    let data = try #require(rep.representation(using: .png, properties: [:]))
    try data.write(to: URL(fileURLWithPath: "/tmp/sillies-speech-bubble-\(name).png"))
    let previews = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      .appendingPathComponent("build/playful-previews/bubbles")
    try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
    try data.write(to: previews.appendingPathComponent("suggestion-\(name).png"), options: .atomic)
  }
}
