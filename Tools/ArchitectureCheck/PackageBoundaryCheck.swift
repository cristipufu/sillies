import SwiftParser
import SwiftSyntax

/// Enforces declared dependency edges as well as imports; adding a dependency cannot bypass the compiler boundary.
final class PackageBoundaryCheck: SyntaxVisitor {
  private(set) var failures: [String] = []
  private static let platformTargets: Set<String> = [
    "SilliesApp", "SilliesWindowMetadata", "WindowMetadataProtocol", "SpeechBenchmark",
    "TextModelBenchmark", "SilliesAudioTestSupport",
  ]

  static func check(_ source: String) -> [String] {
    let tree = Parser.parse(source: source)
    let visitor = PackageBoundaryCheck(viewMode: .sourceAccurate)
    visitor.walk(tree)
    return tree.hasError ? ["Package.swift must parse."] : visitor.failures
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard let call = node.calledExpression.as(MemberAccessExprSyntax.self),
      ["target", "executableTarget"].contains(call.declName.baseName.text)
    else { return .visitChildren }
    guard let name = literal(node.arguments.first { $0.label?.text == "name" }?.expression) else {
      failures.append("Production target names must be explicit literals.")
      return .skipChildren
    }
    guard !Self.platformTargets.contains(name) else { return .skipChildren }
    guard let allowed = ArchitecturePolicy.imports[name] else {
      failures.append("\(name) needs an explicit architecture dependency policy.")
      return .skipChildren
    }
    guard
      let expression = node.arguments.first(where: { $0.label?.text == "dependencies" })?.expression
    else { return .skipChildren }
    guard let dependencies = expression.as(ArrayExprSyntax.self) else {
      failures.append(
        "\(name) dependencies must be explicit; computed dependency lists hide architecture changes."
      )
      return .skipChildren
    }
    for dependency in dependencies.elements {
      let product = dependency.expression.as(FunctionCallExprSyntax.self)
      let target =
        literal(dependency.expression)
        ?? literal(product?.arguments.first { $0.label?.text == "name" }?.expression)
      let audioAdapter = name == "SilliesAudio" && target == "EchoCancellation"
      if let target, allowed.contains(target) || audioAdapter { continue }
      failures.append("\(name) cannot depend on \(target ?? "a computed target").")
    }
    return .skipChildren
  }

  private func literal(_ expression: ExprSyntax?) -> String? {
    guard let value = expression?.as(StringLiteralExprSyntax.self), value.segments.count == 1,
      let segment = value.segments.first?.as(StringSegmentSyntax.self)
    else { return nil }
    return segment.content.text
  }
}
