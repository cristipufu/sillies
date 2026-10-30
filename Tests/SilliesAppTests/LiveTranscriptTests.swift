import AppKit
import SilliesAudioTestSupport
import SilliesCore
import SwiftUI
import Testing

@testable import SilliesApp
@testable import SilliesAudio

private let liveTranscriptFixture = String(
  String(
    repeating: "[09:30] Meeting: We will review the customer proposal on Friday.\n", count: 200
  )
  .suffix(8_192))

@Test @MainActor func transcriptKeepsSelectionAndScrollPositionWhileReading() throws {
  let view = TranscriptScrollView()
  let window = transcriptTestWindow(content: view)
  defer { window.close() }
  view.update(text: liveTranscriptFixture, followMode: .live)
  view.layoutSubtreeIfNeeded()
  #expect(view.textView.bounds.height > view.contentView.bounds.height)
  view.update(text: liveTranscriptFixture, followMode: .reading)
  view.contentView.scroll(to: .zero)
  view.reflectScrolledClipView(view.contentView)
  let selection = NSRange(location: 20, length: 12)
  view.textView.setSelectedRange(selection)
  let latest = String(
    (liveTranscriptFixture + String(repeating: "New speech.\n", count: 100)).suffix(8_192))
  view.update(text: latest, followMode: .reading)
  #expect(view.textView.string == liveTranscriptFixture)
  #expect(view.contentView.bounds.origin.y == 0)
  #expect(view.textView.selectedRange() == selection)
  view.update(text: latest, followMode: .live)
  #expect(view.textView.string == latest)
  #expect(view.contentView.bounds.maxY >= view.textView.bounds.height - 2)
}

@Test @MainActor func selectingSpeechPausesUpdatesAndReturningToBottomResumesThem() {
  let view = TranscriptScrollView()
  let window = transcriptTestWindow(content: view)
  defer { window.close() }
  var modes: [TranscriptScrollView.FollowMode] = []
  view.onFollowModeChange = { modes.append($0) }
  view.update(text: liveTranscriptFixture, followMode: .live)
  view.textView.setSelectedRange(NSRange(location: 20, length: 12))
  #expect(modes.last == .reading)
  let latest = liveTranscriptFixture + "\nLatest words."
  view.update(text: latest, followMode: .reading)
  #expect(view.textView.string == liveTranscriptFixture)
  view.textView.setSelectedRange(NSRange(location: 0, length: 0))
  view.textView.scrollToEndOfDocument(nil)
  NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: view)
  #expect(modes.last == .live)
  #expect(view.textView.string == latest)
}

@Test @MainActor func liveTranscriptStaysAtTheBottomWhenResized() {
  let view = TranscriptScrollView()
  let window = transcriptTestWindow(content: view)
  defer { window.close() }
  view.update(text: liveTranscriptFixture, followMode: .live)
  window.setContentSize(CGSize(width: 560, height: 400))
  view.layoutSubtreeIfNeeded()
  #expect(view.contentView.bounds.maxY >= view.textView.bounds.height - 2)
}

@Test @MainActor func scrollingAwayPausesLiveFollowingAndStopsWithTheView() {
  let view = TranscriptScrollView()
  let window = transcriptTestWindow(content: view)
  defer { window.close() }
  var scrolls = 0
  view.onFollowModeChange = { if $0 == .reading { scrolls += 1 } }
  view.update(text: liveTranscriptFixture, followMode: .live)
  view.contentView.scroll(to: .zero)
  NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: view)
  #expect(scrolls == 1)
  view.stopObserving()
  NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: view)
  #expect(scrolls == 1)
}

@Test(
  arguments: [CompanionSkillKind.listen, .participate],
  [CGSize(width: 640, height: 760), CGSize(width: 560, height: 640)])
@MainActor func populatedTranscriptWindowKeepsUpdatesWithinAFrame(
  _ kind: CompanionSkillKind, size: CGSize
) throws {
  let model = AudioSessionPresentation(kind: kind, sourceLabel: "Synthetic meeting")
  model.phase = .capturing
  model.languages = [fixtureEnglish]
  model.selectedLanguageID = fixtureEnglish.id
  model.isLoadingLanguages = false
  model.followsLiveTranscript = true
  model.transcript = liveTranscriptFixture
  if kind == .participate {
    model.suggestions = (0..<12).map {
      MeetingSuggestion(
        question: "Who will review proposal \($0)?", evidence: "Review is unassigned.",
        elapsed: Double($0) * 60)
    }
  }
  let host = NSHostingView(rootView: AudioSessionView(model: model))
  host.sizingOptions = []
  let window = transcriptTestWindow(content: host, size: size)
  defer { window.close() }
  host.layoutSubtreeIfNeeded()
  let scroll = try #require(findTranscriptScrollView(in: host))
  #expect(scroll.contentView.bounds.height >= 150)
  #expect(scroll.contentView.bounds.height < window.frame.height)
  #expect(host.bounds.contains(scroll.convert(scroll.bounds, to: host)))
  try DisplayFrameSequence.presentCreatedWindows()
  var samples: [Duration] = []
  try DisplayFrameSequence.run(count: 120) { index in
    let start = ContinuousClock.now
    model.transcript = String((model.transcript + " \(index)").suffix(8_192))
    model.elapsed += 0.5
    host.layoutSubtreeIfNeeded()
    host.displayIfNeeded()
    if index >= 5 { samples.append(ContinuousClock.now - start) }
  }
  samples.sort()
  let p95 = samples[Int(Double(samples.count) * 0.95)]
  print("LIVE TRANSCRIPT \(kind) \(size): p95 \(p95)")
  #expect(p95 < .milliseconds(8))
  model.followsLiveTranscript = false
  host.layoutSubtreeIfNeeded()
  #expect(host.bounds.contains(scroll.convert(scroll.bounds, to: host)))
}

@Test @MainActor func audioUIUpdatesCoalesceProgressAndPreserveLifecycleOrder() {
  var received: [AudioCaptureUpdate] = []
  let delivery = AudioSessionUpdateDelivery { received.append($0) }
  delivery.enqueue(.capturing("Fixture"))
  for index in 0..<10_000 {
    delivery.enqueue(.transcript("Draft \(index)", level: 0.2, elapsed: Double(index)))
  }
  delivery.enqueue(.failed("Fixture failure"))
  _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
  #expect(received.count == 3)
  if case .transcript(let text, _, let elapsed) = received.dropFirst().first {
    #expect(text == "Draft 9999" && elapsed == 9_999)
  } else {
    Issue.record("Expected the newest progress snapshot between lifecycle events.")
  }
  delivery.stop()
  delivery.enqueue(.capturing("Stopped"))
  _ = RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
  #expect(received.count == 3)
}

@MainActor private func transcriptTestWindow(
  content: NSView, size: CGSize = CGSize(width: 640, height: 760)
) -> NSWindow {
  _ = NSApplication.shared
  let window = NSWindow(
    contentRect: CGRect(origin: CGPoint(x: 80, y: 80), size: size),
    styleMask: [.titled, .resizable],
    backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  window.contentView = content
  window.orderFront(nil)
  content.layoutSubtreeIfNeeded()
  return window
}

@MainActor func findTranscriptScrollView(in view: NSView) -> TranscriptScrollView? {
  if let scroll = view as? TranscriptScrollView { return scroll }
  return view.subviews.lazy.compactMap { findTranscriptScrollView(in: $0) }.first
}
