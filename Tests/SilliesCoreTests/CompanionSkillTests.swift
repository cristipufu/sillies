import CoreGraphics
import Foundation
import SilliesCore
import Testing

@Suite("CompanionSkill")
struct CompanionSkillTests {
  @Test("Radial skill menu places four skills and hit-tests bubbles")
  func radialMenuHitTesting() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let layout = RadialSkillMenuLayout(
      center: CGPoint(x: 500, y: 400), visibleFrame: screen)
    #expect(layout.items.count == 4)
    #expect(layout.selectedSkill(at: layout.anchor) == nil)
    for item in layout.items {
      #expect(layout.selectedSkill(at: item.center) == item.skill)
      #expect(item.center.y > layout.anchor.y)
    }
  }

  @Test("Radial skill menu flips downward near the top screen edge")
  func radialMenuFlipsDownwardNearTopEdge() {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let layout = RadialSkillMenuLayout(
      center: CGPoint(x: 500, y: 885), visibleFrame: screen)
    #expect(layout.anchor.y <= screen.maxY - RadialSkillMenuLayout.screenMargin)
    for item in layout.items {
      #expect(item.center.y < layout.anchor.y)
    }
  }

  @Test("SessionSummarizer extracts summary bullets and action items")
  func sessionSummarizerExtractsHighlightsAndActions() {
    let transcript = """
      We decided to ship the new companion window binding feature on Friday.
      The audio capture pipeline uses ScreenCaptureKit for isolated app audio.
      TODO: We need to verify reduced motion behavior before release.
      Let's review the Session Vault export format tomorrow morning.
      """
    let result = SessionSummarizer.summarize(
      text: transcript, fallbackContext: "Fallback summary")
    #expect(result.summary.contains("•"))
    #expect(result.actionItems.count == 2)
    #expect(result.actionItems.contains { $0.contains("verify reduced motion") })
    #expect(result.actionItems.contains { $0.contains("Session Vault export") })
  }

  @Test("SessionSummarizer returns fallback when text is empty")
  func sessionSummarizerFallback() {
    let result = SessionSummarizer.summarize(
      text: "   \n  ", fallbackContext: "Captured Zoom window.")
    #expect(result.summary == "Captured Zoom window.")
    #expect(result.actionItems.isEmpty)
  }

  @Test("SessionRecord formats markdown and duration")
  func sessionRecordFormatting() {
    #expect(SessionRecord.formatDuration(0) == "00:00")
    #expect(SessionRecord.formatDuration(125) == "02:05")
    let record = SessionRecord(
      kind: .listen,
      characterID: "mochi",
      characterName: "Mochi",
      appName: "Zoom",
      windowTitle: "Weekly Sync",
      durationSeconds: 125,
      transcript: "Hello team.",
      summary: "• Discussed launch.",
      actionItems: ["Send release notes"])
    let markdown = record.markdownExport
    #expect(markdown.contains("# Zoom — Weekly Sync"))
    #expect(markdown.contains("## Summary"))
    #expect(markdown.contains("- [ ] Send release notes"))
    #expect(markdown.contains("## Transcript\nHello team."))
  }

  @Test("SessionSummarizer bounds work on large transcripts and preserves late action items")
  func sessionSummarizerBoundsLargeInput() async {
    let filler = String(
      repeating:
        "We discussed the architecture and window tracking latency across multiple displays.\n",
      count: 600)
    let tail = "TODO: ship the notarized build with chunked summarization before Friday."
    let result = await SessionSummarizer.summarizeOnWorker(
      text: filler + tail, fallbackContext: "Fallback")
    #expect(result.summary.contains("•"))
    #expect(result.actionItems.contains { $0.contains("ship the notarized build") })
  }

  @Test("SessionSummarizer bounds chunks and output size on 800 KB delimiter-free input")
  func sessionSummarizerBoundsDelimiterFreeInput() async {
    let unpunctuatedFiller = String(
      repeating: "continuous transcript stream without any sentence punctuation ",
      count: 14_000)
    let unpunctuatedTail = "todo verify bounded chunking on unpunctuated streams"
    let unpunctuatedInput = unpunctuatedFiller + unpunctuatedTail
    #expect(unpunctuatedInput.utf8.count >= 800_000)

    let unpunctuatedResult = await SessionSummarizer.summarizeOnWorker(
      text: unpunctuatedInput, fallbackContext: "Fallback")
    #expect(unpunctuatedResult.summary.count <= SessionSummarizer.maxSummaryCharacters)
    #expect(
      unpunctuatedResult.actionItems.allSatisfy {
        $0.count <= SessionSummarizer.maxFragmentCharacters
      })
    #expect(
      unpunctuatedResult.actionItems.contains {
        $0.contains("verify bounded chunking")
      })

    let contiguousToken = String(repeating: "a", count: 820_000)
    let contiguousResult = SessionSummarizer.summarize(
      text: contiguousToken, fallbackContext: "Fallback")
    #expect(contiguousResult.summary.count <= SessionSummarizer.maxSummaryCharacters)
    #expect(
      contiguousResult.actionItems.allSatisfy {
        $0.count <= SessionSummarizer.maxFragmentCharacters
      })
  }

  @Test("SessionSummarizer preserves action phrases split across the 240-character boundary")
  func sessionSummarizerPreservesBoundaryStraddlingActions() {
    // 1. Construct an unpunctuated string where "we" sits right before the 240-character mark
    // and "should ship the release notes" sits immediately after it.
    let prefixUnit = "background discussion about window geometry "
    var prefix = ""
    while prefix.count + prefixUnit.count < 234 {
      prefix += prefixUnit
    }
    if prefix.count < 235 {
      prefix += String(repeating: "x", count: 235 - prefix.count)
    }
    let straddling = prefix + " we should ship the release notes before launch"
    let result = SessionSummarizer.summarize(
      text: straddling, fallbackContext: "Fallback")
    #expect(result.actionItems.count == 1)
    #expect(
      result.actionItems.contains {
        $0.contains("we should ship the release notes")
      })

    // 2. Construct an unpunctuated string where a single TODO starts inside the overlap window
    // before the 240-character mark and its clause continues across the boundary. It must produce
    // exactly one complete checklist entry without a truncated duplicate.
    var todoPrefix = ""
    while todoPrefix.count + prefixUnit.count < 216 {
      todoPrefix += prefixUnit
    }
    if todoPrefix.count < 218 {
      todoPrefix += String(repeating: "x", count: 218 - todoPrefix.count)
    }
    let crossingTodo =
      todoPrefix
      + " TODO: we should verify that overlapping fragments never produce truncated duplicates"
    let todoResult = SessionSummarizer.summarize(
      text: crossingTodo, fallbackContext: "Fallback")
    #expect(todoResult.actionItems.count == 1)
    #expect(
      todoResult.actionItems.first
        == "TODO: we should verify that overlapping fragments never produce truncated duplicates")
  }

  @Test("DropReturnPlan geometry distinguishes perch adjustments from window drops")
  func dropReturnPlanTargetingGeometry() {
    let originWindow = CGRect(x: 100, y: 100, width: 600, height: 400)
    let backgroundWindow = CGRect(x: 80, y: 80, width: 800, height: 600)
    // A small drag near the origin perch over an overlapping background window should not
    // trigger background window controls.
    #expect(
      !DropReturnPlan.shouldShowDragControls(
        targetFrame: backgroundWindow,
        isSameTargetAsAttached: false,
        originWindowFrame: originWindow,
        pointer: CGPoint(x: 90, y: 510),
        companionPoint: CGPoint(x: 120, y: 505),
        characterSize: 64))
    // Moving well inside another window still offers the radial controls while held.
    #expect(
      DropReturnPlan.shouldShowDragControls(
        targetFrame: backgroundWindow,
        isSameTargetAsAttached: false,
        originWindowFrame: originWindow,
        pointer: CGPoint(x: 780, y: 300),
        companionPoint: CGPoint(x: 780, y: 300),
        characterSize: 64))
  }
}
