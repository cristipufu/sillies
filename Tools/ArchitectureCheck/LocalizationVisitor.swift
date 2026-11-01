import SwiftParser
import SwiftSyntax

/// Compiler extraction finds translated strings; this catches display strings omitted from extraction.
final class LocalizationVisitor: SyntaxVisitor {
  private static let nativeLabels: Set<String> = [
    "Text", "Button", "Label", "Toggle", "Picker", "Menu", "Section", "GroupBox",
    "DisclosureGroup", "TextField", "ContentUnavailableView", "ProgressView", "Link",
    "help", "accessibilityLabel", "accessibilityValue", "accessibilityHint", "alert",
    "confirmationDialog",
  ]
  private static let displayArguments: Set<String> = [
    "title", "detail", "subtitle", "withTitle", "feedback", "message", "status",
  ]
  private static let displayProperties: Set<String> = [
    "title", "shortTitle", "explanation", "shortcutExplanation", "statusTitle", "footerMessage",
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
    let tree = Parser.parse(source: source)
    let visitor = LocalizationVisitor(path: path, tree: tree)
    visitor.walk(tree)
    return visitor.diagnostics
  }

  override func visit(_ node: StringLiteralExprSyntax) -> SyntaxVisitorContinueKind {
    guard
      node.segments.contains(where: {
        $0.as(StringSegmentSyntax.self)?.content.text.contains(where: { $0.isLetter }) == true
      })
    else { return .visitChildren }
    let context = Context(node)
    if context.call == "String", context.argument == "localized" { return .visitChildren }
    if context.argument == "verbatim" { return .visitChildren }
    let native = Self.nativeLabels.contains(context.call)
    if native, node.parent?.as(LabeledExprSyntax.self)?.expression.id == node.id {
      return .visitChildren
    }
    let visible =
      context.property == "errorDescription"
      || (path.contains("/UI/")
        && (Self.displayArguments.contains(context.argument)
          || Self.displayProperties.contains(context.property)
          || (native && context.argument.isEmpty)))
    guard visible else { return .visitChildren }
    diagnostics.append(
      .init(
        path: path, line: locations.location(for: node.positionAfterSkippingLeadingTrivia).line,
        rule: "localization",
        message:
          "Localize display copy with String(localized:). Native SwiftUI literal labels are extracted automatically."
      ))
    return .visitChildren
  }

  private struct Context {
    var call = ""
    var argument = ""
    var property = ""
    init(_ node: StringLiteralExprSyntax) {
      var ancestor = node.parent
      var foundArgument = false
      while let item = ancestor {
        if !foundArgument, let value = item.as(LabeledExprSyntax.self) {
          argument = value.label?.text ?? ""
          foundArgument = true
        }
        if call.isEmpty, let value = item.as(FunctionCallExprSyntax.self) {
          call =
            value.calledExpression.as(MemberAccessExprSyntax.self)?.declName.baseName.text
            ?? value.calledExpression.trimmedDescription
        }
        if property.isEmpty, let value = item.as(PatternBindingSyntax.self) {
          property = value.pattern.trimmedDescription
        }
        ancestor = item.parent
      }
    }
  }
}
