import Foundation
import Testing

@testable import SilliesCore

private let highlightGreen = CallSpeakerBorder.Color(red: 72, green: 221, blue: 92)
private let outlineStyle = CallSpeakerBorder.Style(color: highlightGreen, tolerance: 24)
private let videoGray = CallSpeakerBorder.Color(red: 45, green: 45, blue: 45)

@Test func callSpeakerBorderRequiresAThinHighlightOnEveryEdge() {
  let frame = CGRect(x: 20, y: 30, width: 160, height: 90)
  let interior = frame.insetBy(dx: 3, dy: 3)
  #expect(
    CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) {
      interior.contains($0) ? videoGray : highlightGreen
    })
  #expect(
    !CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) { _ in highlightGreen })
  #expect(!CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) { _ in videoGray })
  #expect(
    !CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) {
      $0.y < frame.minY + 3 ? highlightGreen : videoGray
    })
  #expect(!CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) { _ in nil })
  #expect(
    !CallSpeakerBorder.isHighlighted(frame: frame, style: outlineStyle) {
      interior.contains($0) ? videoGray : .init(red: 221, green: 72, blue: 92)
    })
}

@Test func callSpeakerVisualLayoutBoundsNativeGeometryBeforeAllocatingPixels() throws {
  let name = try #require(CallSpeakerName(rawValue: "Alice"))
  let window = CGRect(x: -1600, y: 100, width: 1200, height: 800)
  let tile = CallSpeakerTile(
    name: name, frame: CGRect(x: -1500, y: 150, width: 160, height: 90), audio: .unmuted)
  let layout = try #require(CallSpeakerVisualLayout(windowFrame: window, tiles: [tile]))
  #expect(layout.crop == CGRect(x: 100, y: 50, width: 160, height: 90))
  #expect(layout.imageFrame(for: tile) == CGRect(x: 0, y: 0, width: 160, height: 90))
  #expect(CallSpeakerVisualLayout(windowFrame: window, tiles: []) == nil)
  #expect(CallSpeakerVisualLayout(windowFrame: window, tiles: [tile, tile]) == nil)
  let other = try #require(CallSpeakerName(rawValue: "Bob"))
  let overlapping = CallSpeakerTile(name: other, frame: tile.frame, audio: .unmuted)
  #expect(CallSpeakerVisualLayout(windowFrame: window, tiles: [tile, overlapping]) == nil)
  let distant = CallSpeakerTile(
    name: other, frame: CGRect(x: -600, y: 700, width: 160, height: 90), audio: .unmuted)
  #expect(CallSpeakerVisualLayout(windowFrame: window, tiles: [tile, distant]) == nil)
  for invalid in [
    CGRect(x: -1700, y: 150, width: 160, height: 90),
    CGRect(x: -1500, y: 150, width: 0, height: 90),
    CGRect(x: -1500, y: 150, width: 20, height: 90),
    CGRect(x: Double.nan, y: 150, width: 160, height: 90),
    CGRect(x: -1500, y: 150, width: Double.infinity, height: 90),
  ] {
    #expect(
      CallSpeakerVisualLayout(
        windowFrame: window, tiles: [.init(name: name, frame: invalid, audio: .unmuted)]) == nil)
  }
  let huge = CGRect(x: 0, y: 0, width: 4000, height: 4000)
  #expect(
    CallSpeakerVisualLayout(
      windowFrame: huge, tiles: [.init(name: name, frame: huge, audio: .unmuted)]) == nil)
  #expect(
    !CallSpeakerBorder.isHighlighted(
      frame: CGRect(x: Double.nan, y: 0, width: 100, height: 100), style: outlineStyle
    ) {
      _ in highlightGreen
    })
}
