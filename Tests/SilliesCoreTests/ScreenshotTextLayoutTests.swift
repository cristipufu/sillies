import CoreGraphics
import SilliesCore
import Testing

@Test func screenshotLayoutPreservesIndentationParagraphGapsAndRecognizedWords() {
  let fragments: [ScreenshotTextLayout.Fragment] = [
    .init(text: "start", bounds: .init(x: 0.1, y: 0.9, width: 0.05, height: 0.02)),
    .init(text: "inside", bounds: .init(x: 0.14, y: 0.87, width: 0.06, height: 0.02)),
    .init(text: "Next paragraph — café", bounds: .init(x: 0.1, y: 0.7, width: 0.21, height: 0.02)),
  ]
  #expect(
    ScreenshotTextLayout.text(fragments: fragments) == "start\n    inside\n\nNext paragraph — café")
}

@Test func screenshotLayoutJoinsInlineFragmentsInsteadOfCreatingAStaircase() {
  // Different colors can split a single physical row into several OCR observations.
  let fragments: [ScreenshotTextLayout.Fragment] = [
    .init(text: "Plan", bounds: .init(x: 0.00134, y: 0.89322, width: 0.03948, height: 0.01592)),
    .init(text: "the", bounds: .init(x: 0.0436, y: 0.89412, width: 0.02326, height: 0.01647)),
    .init(text: "next", bounds: .init(x: 0.06977, y: 0.89412, width: 0.02471, height: 0.01412)),
    .init(text: "release", bounds: .init(x: 0.09445, y: 0.89393, width: 0.03784, height: 0.0145)),
    .init(text: "together.", bounds: .init(x: 0.13227, y: 0.89167, width: 0.1, height: 0.01892)),
  ]
  for input in [fragments, fragments.reversed().map { $0 }] {
    #expect(ScreenshotTextLayout.text(fragments: input) == "Plan the next release together.")
  }
}

@Test func screenshotLayoutKeepsToolbarLabelsOnTheirOwnPhysicalRowBelowTheTitle() {
  let fragments: [ScreenshotTextLayout.Fragment] = [
    .init(text: "Files", bounds: .init(x: 0.1, y: 0.8, width: 0.05, height: 0.02)),
    .init(text: "Workspace title", bounds: .init(x: 0.1, y: 0.83, width: 0.25, height: 0.02)),
    .init(text: "View", bounds: .init(x: 0.7, y: 0.8, width: 0.05, height: 0.02)),
    .init(text: "Edit", bounds: .init(x: 0.4, y: 0.8, width: 0.05, height: 0.02)),
  ]
  #expect(ScreenshotTextLayout.text(fragments: fragments) == "Workspace title\nFiles Edit View")
}

@Test func screenshotLayoutReadsIndependentColumnsWithoutInterleavingTheirSentences() {
  var fragments: [ScreenshotTextLayout.Fragment] = [
    .init(text: "Full width heading", bounds: .init(x: 0.1, y: 0.95, width: 0.8, height: 0.02))
  ]
  for (index, y) in [0.85, 0.82, 0.79].enumerated() {
    fragments.append(
      .init(text: "Left \(index)", bounds: .init(x: 0.1, y: y, width: 0.25, height: 0.02)))
    fragments.append(
      .init(text: "Right \(index)", bounds: .init(x: 0.65, y: y, width: 0.25, height: 0.02)))
  }
  for input in [fragments, fragments.reversed().map { $0 }] {
    #expect(
      ScreenshotTextLayout.text(fragments: input)
        == "Full width heading\n\nLeft 0\nLeft 1\nLeft 2\n\nRight 0\nRight 1\nRight 2")
  }
}

@Test func screenshotLayoutUsesTheRecognizedWritingDirectionWithinARow() {
  let fragments: [ScreenshotTextLayout.Fragment] = [
    .init(
      text: "بك", bounds: .init(x: 0.55, y: 0.8, width: 0.1, height: 0.02), direction: .rightToLeft),
    .init(
      text: "مرحبا", bounds: .init(x: 0.7, y: 0.8, width: 0.2, height: 0.02),
      direction: .rightToLeft),
  ]
  #expect(ScreenshotTextLayout.text(fragments: fragments) == "مرحبا بك")
}

@Test func screenshotLayoutKeepsDetectedTableRowsTogetherWithoutRepeatingCells() {
  let table = ScreenshotTextLayout.Table(
    rows: [["Owner", "Task"], ["Alex", "Review"], ["Li", "Tests"]],
    bounds: .init(x: 0.1, y: 0.5, width: 0.8, height: 0.3))
  let fragments = ["Owner", "Alex", "Li", "Task", "Review", "Tests"].map { word in
    ScreenshotTextLayout.Fragment(
      text: word, bounds: .init(x: 0.2, y: 0.6, width: 0.1, height: 0.02))
  }
  #expect(
    ScreenshotTextLayout.text(fragments: fragments, tables: [table])
      == "Owner  Task\nAlex   Review\nLi     Tests")
  #expect(
    ScreenshotTextLayout.text(fragments: [], tables: [table])
      == "Owner  Task\nAlex   Review\nLi     Tests")
}

@Test func screenshotLayoutPreservesTextWhenGeometryIsInvalidOrATableIsEmpty() {
  let invalid = ScreenshotTextLayout.Fragment(
    text: "Unreadable geometry, readable words",
    bounds: .init(x: CGFloat.nan, y: 0, width: 0, height: 0))
  #expect(ScreenshotTextLayout.text(fragments: [invalid]) == "Unreadable geometry, readable words")
  let fragment = ScreenshotTextLayout.Fragment(
    text: "Keep the outside text", bounds: .init(x: 0, y: 0, width: 0.8, height: 0.8))
  let table = ScreenshotTextLayout.Table(
    rows: [["Cell"]], bounds: .init(x: 0.2, y: 0.2, width: 0.5, height: 0.5))
  let text = ScreenshotTextLayout.text(fragments: [fragment], tables: [table])
  #expect(text.contains("Keep the outside text") && text.contains("Cell"))
  let empty = ScreenshotTextLayout.Table(
    rows: [[""]], bounds: .init(x: 0, y: 0, width: 1, height: 1))
  #expect(ScreenshotTextLayout.text(fragments: [fragment], tables: [empty]) == fragment.text)
  #expect(ScreenshotTextLayout.text(fragments: []) == "")
}

@Test func screenshotLayoutPreservesEveryRowAcrossManyWhitespacePartitions() {
  let fragments = (0..<1000).map { index in
    ScreenshotTextLayout.Fragment(
      text: "Row \(index)",
      bounds: .init(x: 0.1, y: 1 - Double(index) / 1000, width: 0.3, height: 0.0004))
  }
  let lines = ScreenshotTextLayout.text(fragments: fragments).split(separator: "\n")
  #expect(lines.map(String.init) == (0..<1000).map { "Row \($0)" })
}
