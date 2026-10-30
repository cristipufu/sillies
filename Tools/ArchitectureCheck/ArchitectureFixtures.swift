import Foundation

/// Positive and negative fixtures prevent accidental file-wide exemptions or comment matches.
enum ArchitectureFixtures {
  struct Fixture {
    let source: String
    let path: String
    let rules: Set<String>
  }
  static func verify() -> Bool {
    let permission = "Sources/SilliesApp/Skills/WindowSnapshotService.swift"
    let rendering = "Sources/SilliesApp/Rendering/CompanionPanel.swift"
    let fixtures: [Fixture] = [
      .init(
        source: "Task.detached { summarize() }", path: "Sources/SilliesCore/Model.swift",
        rules: ["core-effects"]),
      .init(
        source: "nonisolated(unsafe) var state = 0", path: rendering, rules: ["unsafe-isolation"]),
      .init(
        source:
          "Task.detached { SessionSummarizer.summarize(text: text, fallbackContext: fallback) }",
        path: "Sources/SilliesApp/Skills/SessionSummaryWorker.swift", rules: []),
      .init(
        source:
          "Task.detached { work() }; SessionSummarizer.summarize(text: text, fallbackContext: fallback)",
        path: "Sources/SilliesApp/Skills/SessionSummaryWorker.swift", rules: ["ui-io"]),
      .init(
        source: "// try! fatalError()\nlet text = \"process.waitUntilExit()\"", path: rendering,
        rules: []),
      .init(source: "try! read()", path: rendering, rules: ["runtime-trap"]),
      .init(source: "let value = something as! String", path: rendering, rules: ["runtime-trap"]),
      .init(
        source: "panel.setFrame(\n rect,\n display: /* deferred? */ true\n)", path: rendering,
        rules: ["synchronous-display"]),
      .init(source: "panel.setFrame(rect, display: false)", path: rendering, rules: []),
      .init(
        source: "Task.detached { work() }; process.waitUntilExit()", path: permission,
        rules: ["blocking-wait"]),
      .init(source: "Task.detached { process.waitUntilExit() }", path: permission, rules: []),
      .init(
        source: "Task.detached { @MainActor in process.waitUntilExit() }", path: permission,
        rules: ["blocking-wait"]),
      .init(
        source: "Task.detached { await MainActor.run { process.waitUntilExit() } }",
        path: permission, rules: ["blocking-wait"]),
      .init(
        source: "import AppKit", path: "Sources/SilliesAudio/Capture.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import SilliesApp", path: "Sources/SilliesCore/Model.swift",
        rules: ["module-boundary"]),
      .init(
        source: "final class Worker: @unchecked Sendable {}", path: rendering,
        rules: ["unchecked-owner"]),
      .init(
        source: "extension Worker: @unchecked Sendable {}", path: rendering,
        rules: ["unchecked-owner"]),
      .init(
        source:
          "func performRefresh() { work() }; func other() { dispatchPrecondition(condition: .notOnQueue(.main)) }",
        path: "Sources/SilliesApp/Platform/WindowServerSource.swift", rules: ["worker-entry"]),
      .init(
        source:
          "func performRefresh() { dispatchPrecondition(condition: .notOnQueue(.main)); work() }",
        path: "Sources/SilliesApp/Platform/WindowServerSource.swift", rules: []),
      .init(
        source: "CGWindowListCopyWindowInfo(\n options, id)", path: rendering, rules: ["window-ipc"]
      ),
      .init(
        source: "AXUIElementCopyMultipleAttributeValues(window, attrs, 0, &value)", path: rendering,
        rules: ["ax-ipc"]),
      .init(source: "let data = try Data(\n contentsOf: url)", path: rendering, rules: ["ui-io"]),
      .init(source: "func broken(", path: rendering, rules: ["syntax"]),
    ]
    var failures = 0
    for (index, fixture) in fixtures.enumerated() {
      let diagnostics = ArchitectureVisitor.check(
        source: fixture.source, path: fixture.path, policy: .init(uncheckedOwners: [:]))
      let actual = Set(diagnostics.map(\.rule))
      if actual != fixture.rules {
        fputs(
          "Architecture fixture \(index + 1) failed: expected \(fixture.rules), got \(actual)\n",
          stderr)
        failures += 1
      }
    }
    if failures == 0 {
      print("Architecture checker: \(fixtures.count) regression fixtures passed.")
    }
    return failures == 0
  }
}
