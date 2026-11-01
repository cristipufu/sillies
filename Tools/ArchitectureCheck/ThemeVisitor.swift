import SwiftParser
import SwiftSyntax

/// Interface colors are semantic; artwork may continue using its character-defined colors.
final class ThemeVisitor: SyntaxVisitor {
  private static let fixedColors: Set<String> = [
    "white", "red", "green", "orange", "yellow", "blue", "purple", "pink", "gray", "brown",
    "systemRed", "systemGreen", "systemOrange", "systemBlue", "systemPurple",
  ]
  private let path: String
  private let checksColors: Bool
  private let locations: SourceLocationConverter
  private var diagnostics: [ArchitectureDiagnostic] = []

  init(path: String, tree: SourceFileSyntax) {
    self.path = path
    checksColors =
      path.hasPrefix("Sources/SilliesApp/UI/")
      && !["Theme.swift", "DefaultThemeColors.swift"].contains(
        path.split(separator: "/").last.map(String.init) ?? "")
    locations = SourceLocationConverter(fileName: path, tree: tree)
    super.init(viewMode: .sourceAccurate)
  }

  static func check(source: String, path: String) -> [ArchitectureDiagnostic] {
    guard path.hasPrefix("Sources/SilliesApp/") else { return [] }
    let tree = Parser.parse(source: source)
    let visitor = ThemeVisitor(path: path, tree: tree)
    visitor.walk(tree)
    return visitor.diagnostics
  }

  override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
    let callee = node.calledExpression.trimmedDescription
    if [
      "ThemeEnvironment", "ThemeEnvironment.init", "SilliesApp.ThemeEnvironment",
      "SilliesApp.ThemeEnvironment.init",
    ].contains(callee), !isCompositionRoot {
      reportOwnership(node, "Only app composition creates theme environments; inject the owner.")
    }
    if ["NSHostingView", "NSHostingController"].contains(node.calledExpression.trimmedDescription) {
      reportOwnership(node, "Use an explicitly themed hosting root.")
    }
    guard checksColors, ["Color", "NSColor"].contains(node.calledExpression.trimmedDescription)
    else {
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

  override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
    if node.type.trimmedDescription.contains("ThemeEnvironment"), node.defaultValue != nil {
      reportOwnership(node, "Require the theme environment explicitly; do not provide a default.")
    }
    return .visitChildren
  }

  override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
    if ["SilliesTheme", "ThemeEnvironment", "AppWindowAppearance"].contains(
      node.base?.trimmedDescription ?? ""),
      ["shared", "configure"].contains(node.declName.baseName.text)
    {
      reportOwnership(node, "Inject the app-owned theme environment; do not use a global palette.")
    }
    guard checksColors, Self.fixedColors.contains(node.declName.baseName.text),
      node.base == nil || ["Color", "NSColor"].contains(node.base?.trimmedDescription ?? "")
    else { return .visitChildren }
    report(node)
    return .visitChildren
  }

  override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
    for binding in node.bindings where !isCompositionRoot {
      if binding.typeAnnotation?.type.trimmedDescription.contains("ThemeEnvironment") == true,
        let call = binding.initializer?.value.as(FunctionCallExprSyntax.self),
        call.calledExpression.trimmedDescription == ".init"
      {
        reportOwnership(node, "Only app composition creates theme environments; inject the owner.")
      }
    }
    let isStatic = node.modifiers.contains { ["static", "class"].contains($0.name.text) }
    let mentionsOwner = ["ThemeEnvironment", "AppearancePreferences", "AppWindowAppearance"]
      .contains {
        node.bindings.trimmedDescription.contains($0)
      }
    let mutablePalette =
      node.bindingSpecifier.text == "var"
      && node.bindings.trimmedDescription.contains("SilliesTheme")
    if isStatic && (mentionsOwner || mutablePalette) {
      reportOwnership(
        node, "Theme preferences and environments must have an injected instance owner.")
    }
    return .visitChildren
  }

  private var isCompositionRoot: Bool { path == "Sources/SilliesApp/App/SilliesMain.swift" }

  private func reportOwnership(_ node: some SyntaxProtocol, _ message: String) {
    diagnostics.append(
      .init(
        path: path,
        line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
        rule: "theme-ownership", message: message))
  }

  private func report(_ node: some SyntaxProtocol) {
    diagnostics.append(
      .init(
        path: path, line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
        rule: "theme-colors", message: "Use a SilliesTheme semantic role for interface colors."))
  }
}
