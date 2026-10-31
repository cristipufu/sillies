import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func dropHighlightPreparesNativeBackingWithoutShowingOrInterceptingInput() throws {
  _ = NSApplication.shared
  let highlight = WindowDropHighlightController()
  defer { highlight.close() }
  highlight.prestage(target: SkillOverlayPreparation.target)
  let number = try #require(highlight.windowNumber)
  let window = try #require(NSApp.window(withWindowNumber: number))
  #expect(window.isVisible)
  #expect(window.alphaValue == 0)
  #expect(window.ignoresMouseEvents)
  #expect(!highlight.isVisible)
  highlight.conceal()
  #expect(window.isVisible, "The initial drag-distance gate must retain the staged backing.")
  highlight.show(target: SkillOverlayPreparation.target, hoveredSkill: nil)
  #expect(highlight.isVisible)
  highlight.hide()
  #expect(!window.isVisible, "Ending a drag must order out the staged window.")
}
