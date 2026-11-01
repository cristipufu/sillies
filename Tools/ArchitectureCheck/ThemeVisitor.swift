import SwiftParser
import SwiftSyntax

/// Interface colors are semantic; artwork may continue using its character-defined colors.
final class ThemeVisitor: SyntaxVisitor {
  private static let fixedColors: Set<String> = [
    "white", "red", "green", "orange", "yellow", "blue", "purple", "pink", "gray", "brown",
    "systemRed", "systemGreen", "systemOrange", "systemBlue", "systemPurple",
  ]
  private let path: String
  private let locations: SourceLocationConverter
  private var diagnostics: [ArchitectureDiagnostic] = []

  init(path: String, tree: SourceFileSyntax) {
    self.path = path
    locations = SourceLocationConverter(fileName: path, tree: tree)
    super.init(viewMode: .sourceAccurate)
  }

  static func check(source: String, path: String) -> [ArchitectureDiagnostic] {
    guard path.hasPrefix("Sources/SilliesApp/UI/"),
      !["Theme.swift", "DefaultThemeColors.swift"].contains(
        path.split(separator: "/").last.map(String.init) ?? "")
    else { return [] }
    let tree = Parser.parse(source: source)
    let visitor = ThemeVisitor(path: path, tree: tree)
    visitor.walk(tree)
    return visitor.diagnostics
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    guard ["Color", "NSColor"].contains(node.calledExpression.trimmedDescription) else {
      return .visitChildren
    }
    let fixed = node.arguments.contains { argument in
      guard ["hex", "red", "srgbRed", "white"].contains(argument.label?.text ?? "") else {
        return false
      }
      return argument.expression.is(StringLiteralExprSyntax.self)
        || argument.expression.is(FloatLiteralExprSyntax.self)
        || argument.expression.is(IntegerLiteralExprSyntax.self)
    }
    if fixed { report(node) }
    return .visitChildren
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    guard Self.fixedColors.contains(node.declName.baseName.text),
      node.base == nil || ["Color", "NSColor"].contains(node.base?.trimmedDescription ?? "")
    else { return .visitChildren }
    report(node)
    return .visitChildren
  }

  private func report(_ node: some SyntaxProtocol) {
    diagnostics.append(
      .init(
        path: path, line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
        rule: "theme-colors", message: "Use a SilliesTheme semantic role for interface colors."))
  }
}
