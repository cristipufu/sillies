import SwiftParser
import SwiftSyntax

/// Checks parsed expressions and declarations; comments and unrelated calls cannot satisfy a rule.
final class ArchitectureVisitor: SyntaxVisitor {
  private let path: String
  private let policy: ArchitecturePolicy
  private let locations: SourceLocationConverter
  private(set) var diagnostics: [ArchitectureDiagnostic] = []

  init(path: String, tree: SourceFileSyntax, policy: ArchitecturePolicy) {
    self.path = path
    self.policy = policy
    locations = SourceLocationConverter(fileName: path, tree: tree)
    super.init(viewMode: .sourceAccurate)
  }

  static func check(source: String, path: String, policy: ArchitecturePolicy)
    -> [ArchitectureDiagnostic]
  {
    let tree = Parser.parse(source: source)
    let visitor = ArchitectureVisitor(path: path, tree: tree, policy: policy)
    if tree.hasError {
      visitor.report(tree, "syntax", "Source must parse before checking its architecture.")
    }
    visitor.walk(tree)
    return visitor.diagnostics
  }

  private func report(_ node: some SyntaxProtocol, _ rule: String, _ message: String) {
    diagnostics.append(
      .init(
        path: path, line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
        rule: rule, message: message))
  }

  override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
    let module = node.path.first?.name.text ?? ""
    let owner = path.split(separator: "/").dropFirst().first.map(String.init) ?? ""
    if let allowed = ArchitecturePolicy.imports[owner], !allowed.contains(module) {
      report(node, "module-boundary", "\(owner) cannot import \(module).")
    }
    if ["MLX", "MLXLLM", "MLXLMCommon", "Tokenizers"].contains(module),
      owner != "SilliesTextInference"
    {
      report(
        node, "inference-isolation", "Downloaded text inference SDKs belong in the helper process.")
    }
    return .skipChildren
  }

  override func visit(_ node: TryExprSyntax) -> SyntaxVisitorContinueKind {
    if node.questionOrExclamationMark?.text == "!" {
      report(node, "runtime-trap", "Handle errors instead of forcing try.")
    }
    return .visitChildren
  }

  override func visit(_ node: ForceUnwrapExprSyntax) -> SyntaxVisitorContinueKind {
    report(node, "runtime-trap", "Handle missing values instead of force-unwrapping them.")
    return .visitChildren
  }

  override func visit(_ node: AsExprSyntax) -> SyntaxVisitorContinueKind {
    if node.questionOrExclamationMark?.text == "!" {
      report(node, "runtime-trap", "Use a checked cast.")
    }
    return .visitChildren
  }

  override func visit(_ node: UnresolvedAsExprSyntax) -> SyntaxVisitorContinueKind {
    if node.questionOrExclamationMark?.text == "!" {
      report(node, "runtime-trap", "Use a checked cast.")
    }
    return .visitChildren
  }

  override func visit(_ node: DeclModifierSyntax) -> SyntaxVisitorContinueKind {
    if compact(node) == "nonisolated(unsafe)" {
      report(node, "unsafe-isolation", "Give mutable state an actor, queue, or Mutex owner.")
    }
    return .visitChildren
  }

  override func visit(_ node: InheritedTypeSyntax) -> SyntaxVisitorContinueKind {
    if compact(node.type).contains("@unchecked"), compact(node.type).hasSuffix("Sendable") {
      let key = path + "#" + declaringType(node)
      if policy.uncheckedOwners[key]?.isEmpty != false {
        report(
          node, "unchecked-owner",
          "Document the confinement and lifetime of \(key), or use checked Sendable.")
      }
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    let filename = path.split(separator: "/").last.map(String.init) ?? ""
    if ArchitecturePolicy.workerEntries[filename]?.contains(node.name.text) == true {
      let first = node.body?.statements.first.map { compact($0.item) }
      let condition =
        filename == "SerialQueueStorage.swift" ? ".onQueue(queue)" : ".notOnQueue(.main)"
      if first != "dispatchPrecondition(condition:\(condition))" {
        report(node, "worker-entry", "\(node.name.text) must assert \(condition) at entry.")
      }
    }
    return .visitChildren
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    let expression = compact(node.calledExpression)
    let name =
      node.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
      ?? node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text ?? expression
    if path.hasPrefix("Sources/SilliesCore/"),
      ["Task", "Timer", "DispatchQueue", "FileManager", "URLSession"].contains(where: {
        expression == $0 || expression.hasPrefix($0 + ".")
      })
    {
      report(
        node, "core-effects",
        "Core owns pure decisions; schedule work and perform I/O in the platform layer.")
    }
    checkBlocking(node, expression: expression, name: name)
    checkPlatformAccess(node, expression: expression, name: name)
    checkPresentation(node, expression: expression, name: name)
    return .visitChildren
  }

  private func checkBlocking(_ node: FunctionCallExprSyntax, expression: String, name: String) {
    if ["fatalError", "preconditionFailure"].contains(name) {
      report(node, "runtime-trap", "Handle this failure without a runtime trap.")
    }
    if name == "waitUntilExit" {
      if path != "Sources/SilliesApp/Skills/WindowSnapshotService.swift"
        || !isInsideDetachedWork(node)
      {
        report(
          node, "blocking-wait",
          "Process waits require an audited detached worker closure.")
      }
    } else if [
      "wait", "sync", "usleep", "DispatchSemaphore", "DispatchGroup", "NSCondition",
      "NSConditionLock",
    ].contains(name) || expression == "Thread.sleep" {
      report(node, "blocking-wait", "Use asynchronous completion instead of a blocking wait.")
    }
    let inUI = path.contains("/UI/") || path.contains("/Rendering/")
    if inUI, ["Data", "String", "NSImage"].contains(name),
      node.arguments.contains(where: { $0.label?.text == "contentsOf" })
    {
      report(node, "ui-io", "Load files and decode images on a worker.")
    }
    if expression == "SessionSummarizer.summarize", path.hasPrefix("Sources/SilliesApp/") {
      if path != "Sources/SilliesApp/Skills/SessionSummaryWorker.swift"
        || !isInsideDetachedWork(node)
      {
        report(node, "ui-io", "Use SessionSummaryWorker.summarize.")
      }
    }
  }

  private func checkPlatformAccess(_ node: FunctionCallExprSyntax, expression: String, name: String)
  {
    if ["UInt32", "CGWindowID"].contains(name),
      node.arguments.contains(where: { argument in
        argument.expression.tokens(viewMode: .sourceAccurate).contains { $0.text == "windowNumber" }
      }),
      path != "Sources/SilliesApp/Platform/NativeWindowIdentity.swift"
        || node.arguments.first?.label?.text != "exactly"
    {
      report(
        node, "window-identity", "Use NSWindow.windowServerID to validate AppKit window numbers.")
    }
    if [
      "CGWindowListCopyWindowInfo", "CGWindowListCreate", "CGWindowListCreateDescriptionFromArray",
    ].contains(name), path != "Sources/SilliesWindowMetadata/WindowMetadataService.swift" {
      report(node, "window-ipc", "Window-list access belongs to the metadata helper process.")
    }
    if name.hasPrefix("AXUIElementCopy") || name == "AXUIElementSetAttributeValue"
      || name == "AXUIElementIsAttributeSettable",
      ![
        "Sources/SilliesApp/Platform/AccessibilityWindowSource.swift",
        "Sources/SilliesApp/Platform/AccessibilityTextAccess.swift",
      ].contains(path)
    {
      report(node, "ax-ipc", "Accessibility access belongs to the isolated window or text worker.")
    }
    if name == "postToPid", path != "Sources/SilliesApp/Platform/ClipboardPasteTransaction.swift" {
      report(
        node, "text-insertion", "Targeted paste events belong to the clipboard transaction worker.")
    }
    if name == "writeObjects", path != "Sources/SilliesApp/Platform/ClipboardPasteTransaction.swift"
    {
      report(node, "clipboard-encoding", "Write pre-encoded image data.")
    }
  }

  private func checkPresentation(_ node: FunctionCallExprSyntax, expression: String, name: String) {
    let overlay =
      path.contains("/Rendering/") || path.hasSuffix("/CompanionInstance.swift")
      || path.hasSuffix("/SkillOverlayWindow.swift")
    if overlay, name == "setFrame",
      node.arguments.contains(where: {
        $0.label?.text == "display" && compact($0.expression) != "false"
      })
    {
      report(node, "synchronous-display", "Overlay setFrame must specify display: false.")
    }
    if path.contains("/Rendering/"), expression.hasSuffix("workspaceMotion.presentation") {
      report(node, "render-readback", "Keep motion state instead of reading the presentation tree.")
    }
    if path.hasSuffix("/SkillOverlayWindow.swift"), name == "CAShapeLayer" {
      report(node, "raster-outline", "Use a composited CALayer border.")
    }
  }

  private func isInsideDetachedWork(_ node: some SyntaxProtocol) -> Bool {
    var ancestor = node.parent
    while let current = ancestor {
      if let closure = current.as(ClosureExprSyntax.self) {
        if closure.signature?.attributes.contains(where: { compact($0) == "@MainActor" }) == true {
          return false
        }
        // Only a direct detached closure qualifies. A nested Task or MainActor.run does not.
        guard let call = closure.parent?.as(FunctionCallExprSyntax.self) else { return false }
        return compact(call.calledExpression) == "Task.detached"
      }
      if current.is(FunctionDeclSyntax.self) { return false }
      ancestor = current.parent
    }
    return false
  }

  private func declaringType(_ node: some SyntaxProtocol) -> String {
    var ancestor = node.parent
    while let current = ancestor {
      if let declaration = current.as(ClassDeclSyntax.self) { return declaration.name.text }
      if let declaration = current.as(StructDeclSyntax.self) { return declaration.name.text }
      if let declaration = current.as(ExtensionDeclSyntax.self) {
        return compact(declaration.extendedType)
      }
      ancestor = current.parent
    }
    return "unknown"
  }

  private func compact(_ node: some SyntaxProtocol) -> String {
    node.tokens(viewMode: .sourceAccurate).map(\.text).joined()
  }
}
