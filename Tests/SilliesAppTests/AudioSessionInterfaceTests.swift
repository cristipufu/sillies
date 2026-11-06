import AppKit
import SilliesAudioTestSupport
import SilliesCore
import SilliesModelStore
import SwiftUI
import Testing

@testable import SilliesApp

@Test @MainActor func participatePanesFitLongSuggestionsAndNoticesWithoutNestedScrolling() throws {
  let model = try participateLayoutFixture()
  for scheme in [ColorScheme.light, .dark] {
    for pane in [AudioSessionPresentation.DetailPane.transcript, .suggestions] {
      model.selectDetailPane(pane)
      try renderSkillInterface(
        AudioSessionView(model: model).environment(\.colorScheme, scheme),
        size: SessionWindowLayout.minimumSize, name: "sillies-participate-\(pane)-\(scheme)")
    }
  }
  model.phase = .failed(.permissionDenied(.openScreenRecordingSettings))
  model.transcriptionFailure = .permissionDenied(.openMicrophoneSettings)
  model.speakerDetectionNotice = String(repeating: "Speaker labels are unavailable. ", count: 8)
  model.reasoningNotice = String(
    repeating: "Suggestions are unavailable for this language. ", count: 8)
  for pane in [AudioSessionPresentation.DetailPane.transcript, .suggestions] {
    model.selectDetailPane(pane)
    try renderSkillInterface(
      AudioSessionView(model: model), size: SessionWindowLayout.minimumSize,
      name: "sillies-participate-failure-\(pane)")
  }
  model.suggestions = []
  try renderSkillInterface(
    AudioSessionView(model: model), size: SessionWindowLayout.minimumSize,
    name: "sillies-participate-empty-suggestions")
  model.phase = .paused
  model.transcriptionFailure = nil
  model.speakerDetectionNotice = nil
  model.reasoningNotice = nil
  model.pendingLanguageID = fixtureFrench.id
  model.selectDetailPane(.transcript)
  model.transcript = ""
  try renderSkillInterface(
    AudioSessionView(model: model), size: SessionWindowLayout.minimumSize,
    name: "sillies-participate-changing-language")
}

@Test @MainActor func participateSwitchingPanesPreservesTheNativeTranscriptAndSelection() throws {
  let model = try participateLayoutFixture()
  let window = NSWindow(
    contentRect: CGRect(origin: .zero, size: SessionWindowLayout.minimumSize),
    styleMask: [.borderless], backing: .buffered, defer: false)
  window.isReleasedWhenClosed = false
  defer { window.close() }
  let host = NSHostingView(rootView: AudioSessionView(model: model))
  host.sizingOptions = []
  window.contentView = host
  host.layoutSubtreeIfNeeded()
  let transcript = try #require(findTranscriptScrollView(in: host))
  #expect(transcript.contentView.bounds.height >= 150)
  assertUnnestedScrollViews(in: host)
  model.followsLiveTranscript = false
  host.layoutSubtreeIfNeeded()
  transcript.contentView.scroll(to: .zero)
  transcript.reflectScrolledClipView(transcript.contentView)
  let selection = NSRange(location: 20, length: 12)
  transcript.textView.setSelectedRange(selection)
  #expect(window.makeFirstResponder(transcript.textView))
  let originalText = transcript.textView.string
  let originalOffset = transcript.contentView.bounds.origin

  model.selectDetailPane(.suggestions)
  model.transcript += "\nNew speech while reading suggestions."
  host.layoutSubtreeIfNeeded()
  assertUnnestedScrollViews(in: host)
  #expect(findTranscriptScrollView(in: host) === transcript)
  #expect(transcript.isHidden)
  #expect(window.firstResponder !== transcript.textView)
  model.selectDetailPane(.transcript)
  host.layoutSubtreeIfNeeded()
  #expect(findTranscriptScrollView(in: host) === transcript)
  #expect(!transcript.isHidden)
  #expect(transcript.textView.string == originalText)
  #expect(transcript.textView.selectedRange() == selection)
  #expect(transcript.contentView.bounds.origin == originalOffset)
  #expect(!model.followsLiveTranscript)
  model.followsLiveTranscript = true
  host.layoutSubtreeIfNeeded()
  #expect(transcript.textView.string == model.transcript)
}

@Test @MainActor func closingMeetingDetailsLeavesLaterSuggestionsUnread() throws {
  let model = try participateLayoutFixture()
  let controller = AudioSessionWindowController(appearance: ThemeEnvironment())
  controller.prepare(model)
  let window = try #require(controller.window)
  #expect(!window.isVisible)
  #expect(window.delegate === controller)
  model.showDetails()
  model.selectDetailPane(.suggestions)
  window.close()
  model.updateSuggestions(model.suggestions)
  #expect(model.hasUnreadSuggestion)
  controller.close()
  #expect(controller.window == nil)
}

@Test @MainActor func meetingSuggestionsStayUnreadUntilTheirPaneIsShown() {
  let model = AudioSessionPresentation(kind: .participate, sourceLabel: "Fixture meeting")
  let suggestion = MeetingSuggestion(
    question: "Who will review?", evidence: "Review is unassigned.", elapsed: 10)
  model.showDetails()
  model.updateSuggestions([suggestion])
  #expect(model.hasUnreadSuggestion)
  #expect(model.detailPane == .transcript)
  model.selectDetailPane(.suggestions)
  #expect(!model.hasUnreadSuggestion)
  model.updateSuggestions([suggestion])
  #expect(!model.hasUnreadSuggestion)
  model.hideDetails()
  model.updateSuggestions([suggestion])
  #expect(model.hasUnreadSuggestion)
  model.showDetails()
  #expect(model.detailPane == .suggestions)
  #expect(!model.hasUnreadSuggestion)
}

@MainActor private func assertUnnestedScrollViews(in view: NSView) {
  if view is NSScrollView {
    var ancestor = view.superview
    while let current = ancestor {
      #expect(
        !(current is NSScrollView),
        "Each reading pane must own a single independent scroll viewport")
      ancestor = current.superview
    }
  }
  for child in view.subviews { assertUnnestedScrollViews(in: child) }
}

@MainActor private func participateLayoutFixture() throws -> AudioSessionPresentation {
  let catalog = try SpeechModelCatalog.bundled()
  let model = AudioSessionPresentation(
    kind: .participate, sourceLabel: "Design review · Meeting + microphone")
  model.model = try catalog.manifest(for: "parakeet-ultra").model
  model.diarizationModel = try catalog.manifest(for: "nemotron-speakers").model
  model.phase = .capturing
  model.elapsed = 125
  model.languages = [fixtureEnglish, fixtureFrench]
  model.selectedLanguageID = fixtureEnglish.id
  model.isLoadingLanguages = false
  model.transcript = String(
    repeating: "[02:05] Meeting: We will review the launch proposal on Friday.\n", count: 80)
  model.suggestions = (0..<12).map { index in
    MeetingSuggestion(
      question:
        "Who will review the proposal and confirm the customer’s requirements before the launch?",
      evidence: String(
        repeating: "The proposal is due next week, but the review is still unassigned. ", count: 5),
      elapsed: TimeInterval(index * 60))
  }
  return model
}
