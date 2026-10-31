import Foundation

/// Positive and negative fixtures prevent accidental file-wide exemptions or comment matches.
enum ArchitectureFixtures {
  private static func verifyPackageBoundaries() -> Bool {
    let valid = [
      "let t = [.target(name: \"SilliesWriting\", dependencies: [\"SilliesCore\", \"SilliesAudio\", \"SilliesReasoning\"]) ]",

      "let t = [.target(name: \"SilliesReasoning\", dependencies: [\"SilliesCore\", \"SilliesTextModels\"])]",
      "let t = [.target(name: \"SilliesVault\", dependencies: [\"SilliesCore\", \"SilliesPersistence\"])]",
    ]
    let invalid = [
      "let t = [.target(name: \"SilliesWriting\", dependencies: [\"SilliesApp\"])]",
      "let t = [.target(name: \"SilliesWriting\", dependencies: [\"SilliesPersistence\"])]",
      "let t = [.target(name: \"SilliesWriting\", dependencies: [\"SilliesSpeechApple\"])]",

      "let t = [.target(name: \"SilliesReasoning\", dependencies: [\"SilliesApp\"])]",
      "let t = [.target(name: \"SilliesVault\", dependencies: [\"SilliesAudio\"])]",
      "let t = [.target(name: \"SilliesCore\", dependencies: injectedDependencies)]",
      "let t = [.target(name: \"UnreviewedFeature\", dependencies: [])]",
    ]
    let success =
      valid.allSatisfy { PackageBoundaryCheck.check($0).isEmpty }
      && invalid.allSatisfy { !PackageBoundaryCheck.check($0).isEmpty }
    if !success {
      fputs("Package boundary fixtures failed.\n", stderr)
    } else {
      print("Package boundaries: \(valid.count + invalid.count) regression fixtures passed.")
    }
    return success
  }
  struct Fixture {
    let source: String
    let path: String
    let rules: Set<String>
  }
  static func verify() -> Bool {
    guard verifyPackageBoundaries() else { return false }
    let permission = "Sources/SilliesApp/Skills/WindowSnapshotService.swift"
    let rendering = "Sources/SilliesApp/Rendering/CompanionPanel.swift"
    let fixtures: [Fixture] = [
      .init(
        source: "let defaults = UserDefaults.standard",
        path: "Sources/SilliesWriting/NewWorkflow.swift", rules: ["writing-boundary"]),
      .init(
        source: "let files = FileManager.default", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["writing-boundary"]),
      .init(
        source: "let worker = Process()", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["writing-boundary"]),

      .init(
        source: "import AppKit", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import SilliesApp", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import SilliesPersistence", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import SilliesSpeechApple", path: "Sources/SilliesWriting/NewWorkflow.swift",
        rules: ["module-boundary"]),
      .init(
        source: "class Workflow { static let shared = Workflow() }",
        path: "Sources/SilliesWriting/NewWorkflow.swift", rules: ["service-lifetime"]),
      .init(
        source: "let history: any WritingHistoryRecording",
        path: "Sources/SilliesWriting/NewWorkflow.swift", rules: []),

      .init(
        source: "import AppKit", path: "Sources/SilliesReasoning/NewFeature.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import SilliesApp", path: "Sources/SilliesVault/NewFeature.swift",
        rules: ["module-boundary"]),
      .init(
        source: "func build() { let engine = LocalReasoningService(backend: backend) }",
        path: "Sources/SilliesApp/UI/NewView.swift", rules: ["reasoning-boundary"]),
      .init(
        source: "typealias Engine = SilliesReasoning.LocalReasoningService",
        path: "Sources/SilliesApp/Skills/NewFeature.swift", rules: ["reasoning-boundary"]),
      .init(
        source: "func build() { let factory = LocalReasoningService.init }",
        path: "Sources/SilliesApp/Skills/NewFeature.swift", rules: ["reasoning-boundary"]),
      .init(
        source: "let engine: any LocalReasoning",
        path: "Sources/SilliesApp/Skills/NewFeature.swift", rules: []),
      .init(
        source: "class Services { let engine = LocalReasoningService(backend: backend) }",
        path: "Sources/SilliesApp/App/Composition/NewComposition.swift", rules: []),
      .init(
        source: "actor Engine { static let shared = Engine() }",
        path: "Sources/SilliesReasoning/NewFeature.swift", rules: ["service-lifetime"]),
      .init(
        source: "enum Services { static let engine = LocalReasoningService(backend: backend) }",
        path: "Sources/SilliesApp/App/Composition/NewComposition.swift", rules: ["service-lifetime"]
      ),
      .init(
        source: "let engine = LocalReasoningService(backend: backend)",
        path: "Sources/SilliesApp/App/Composition/NewComposition.swift", rules: ["service-lifetime"]
      ),
      .init(
        source: "init(backend: any ReasoningBackend = AppleReasoningBackend()) {}",
        path: "Sources/SilliesReasoning/NewFeature.swift", rules: ["dependency-default"]),
      .init(
        source: "let controller: CompanionController",
        path: "Sources/SilliesApp/App/WritingTools.swift", rules: ["writing-boundary"]),
      .init(
        source: "let skills = SkillCoordinator()",
        path: "Sources/SilliesApp/App/WritingTools.swift", rules: ["writing-boundary"]),
      .init(
        source: "let host: any WritingCompanionHost",
        path: "Sources/SilliesApp/App/WritingTools.swift", rules: []),
      .init(
        source: "let controller: CompanionController",
        path: "Sources/SilliesApp/App/SilliesMain.swift", rules: []),
      .init(
        source: "import MLX", path: "Sources/SilliesApp/Skills/Text.swift",
        rules: ["inference-isolation"]),
      .init(source: "import MLX", path: "Sources/SilliesTextInference/Runtime.swift", rules: []),
      .init(
        source: "import AppKit", path: "Sources/SilliesTextModels/Provider.swift",
        rules: ["module-boundary"]),
      .init(
        source: "Task.detached { process.waitUntilExit() }",
        path: "Sources/SilliesTextModels/TextWorkerConnection.swift", rules: ["blocking-wait"]),
      .init(
        source: "process.waitUntilExit()",
        path: "Sources/SilliesTextModels/TextWorkerConnection.swift", rules: ["blocking-wait"]),
      .init(
        source: "import WhisperKit", path: "Sources/SilliesAudio/Capture.swift",
        rules: ["module-boundary"]),
      .init(
        source: "import AppKit", path: "Sources/SilliesModelStore/Store.swift",
        rules: ["module-boundary"]),
      .init(
        source: "func load() { readWeights() }",
        path: "Sources/SilliesSpeechWhisper/WhisperWindowEngine.swift", rules: ["worker-entry"]),
      .init(
        source:
          "func load() { dispatchPrecondition(condition: .notOnQueue(.main)); readWeights() }",
        path: "Sources/SilliesSpeechWhisper/WhisperWindowEngine.swift", rules: []),
      .init(
        source: "func withValue() { access() }",
        path: "Sources/SilliesAudio/SerialQueueStorage.swift", rules: ["worker-entry"]),
      .init(
        source: "func withValue() { dispatchPrecondition(condition: .onQueue(queue)); access() }",
        path: "Sources/SilliesAudio/SerialQueueStorage.swift", rules: []),
      .init(
        source: "Task.detached { summarize() }", path: "Sources/SilliesCore/Model.swift",
        rules: ["core-effects"]),
      .init(
        source: "nonisolated(unsafe) var state = 0", path: rendering, rules: ["unsafe-isolation"]),
      .init(
        source:
          "Task.detached { SessionSummarizer.summarize(text: text, fallbackContext: fallback) }",
        path: "Sources/SilliesReasoning/SessionSummaryWorker.swift", rules: []),
      .init(
        source:
          "Task.detached { work() }; SessionSummarizer.summarize(text: text, fallbackContext: fallback)",
        path: "Sources/SilliesReasoning/SessionSummaryWorker.swift", rules: ["ui-io"]),
      .init(
        source: "// try! fatalError()\nlet text = \"process.waitUntilExit()\"", path: rendering,
        rules: []),
      .init(source: "try! read()", path: rendering, rules: ["runtime-trap"]),
      .init(source: "let value = result!", path: rendering, rules: ["runtime-trap"]),
      .init(source: "if let value = result { use(value) }", path: rendering, rules: []),
      .init(source: "UInt32(window.windowNumber)", path: rendering, rules: ["window-identity"]),
      .init(source: "CGWindowID(windowNumber)", path: rendering, rules: ["window-identity"]),
      .init(
        source: "Swift.UInt32(window.windowNumber)", path: rendering, rules: ["window-identity"]),
      .init(source: "window.windowServerID", path: rendering, rules: []),
      .init(
        source: "CGWindowID(exactly: windowNumber)",
        path: "Sources/SilliesApp/Platform/NativeWindowIdentity.swift", rules: []),
      .init(
        source: "CGWindowID(windowNumber)",
        path: "Sources/SilliesApp/Platform/NativeWindowIdentity.swift", rules: ["window-identity"]),
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
      .init(
        source: "AXUIElementSetAttributeValue(field, attribute, text)", path: rendering,
        rules: ["ax-ipc"]),
      .init(
        source: "AXUIElementIsAttributeSettable(field, attribute, &result)", path: rendering,
        rules: ["ax-ipc"]),
      .init(
        source: "AXUIElementCopyAttributeValue(field, attribute, &result)",
        path: "Sources/SilliesApp/Platform/AccessibilityTextAccess.swift", rules: []),
      .init(source: "board.writeObjects(items)", path: rendering, rules: ["clipboard-encoding"]),
      .init(
        source: "board.writeObjects(items)",
        path: "Sources/SilliesApp/Platform/ClipboardPasteTransaction.swift", rules: []),
      .init(source: "event.postToPid(pid)", path: rendering, rules: ["text-insertion"]),
      .init(
        source: "event.postToPid(pid)",
        path: "Sources/SilliesApp/Platform/ClipboardPasteTransaction.swift", rules: []),
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
