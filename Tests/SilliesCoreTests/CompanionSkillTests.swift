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

  @Test("SessionSummarizer bounds work on large transcripts")
  func sessionSummarizerBoundsLargeInput() {
    let repeated = String(
      repeating:
        "We decided on the release plan for Sillies. TODO: verify notarization and Sparkle feed.\n",
      count: 2_000)
    let result = SessionSummarizer.summarize(text: repeated, fallbackContext: "Fallback")
    #expect(result.summary.contains("•"))
    #expect(!result.actionItems.isEmpty)
  }

  @Test("DropReturnPlan geometry distinguishes perch adjustments from window drops")
  func dropReturnPlanTargetingGeometry() {
    let originWindow = CGRect(x: 100, y: 100, width: 600, height: 400)
    let backgroundWindow = CGRect(x: 80, y: 80, width: 800, height: 600)
    // A small drag near the origin perch over an overlapping background window should not
    // trigger background window controls or accidental rebinding.
    #expect(
      !DropReturnPlan.shouldShowDragControls(
        targetFrame: backgroundWindow,
        isSameTargetAsAttached: false,
        originWindowFrame: originWindow,
        pointer: CGPoint(x: 90, y: 510),
        companionPoint: CGPoint(x: 120, y: 505),
        characterSize: 64))
    #expect(
      !DropReturnPlan.shouldBindOnDrop(
        targetFrame: backgroundWindow,
        currentAttachedWindowFrame: originWindow,
        pointer: CGPoint(x: 96, y: 510),
        companionPoint: CGPoint(x: 120, y: 505),
        characterSize: 64))

    // Dropping well inside a target window's interior binds to that target.
    #expect(
      DropReturnPlan.shouldBindOnDrop(
        targetFrame: backgroundWindow,
        currentAttachedWindowFrame: originWindow,
        pointer: CGPoint(x: 780, y: 300),
        companionPoint: CGPoint(x: 780, y: 300),
        characterSize: 64))
  }
}
