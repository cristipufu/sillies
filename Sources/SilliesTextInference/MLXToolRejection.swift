import MLXLMCommon
import SilliesTextModels

extension TextGenerationFailure.ToolRejection {
  /// Never transfer the rejected payload, arguments or private reasoning into diagnostics.
  init(_ rejection: RejectedToolCall) {
    let reason: Reason
    switch rejection.reason {
    case .malformedSyntax: reason = .malformedSyntax
    case .incompleteOutput: reason = .incompleteOutput
    case .missingToolName: reason = .missingToolName
    case .undeclaredTool: reason = .undeclaredTool
    case .invalidArguments: reason = .invalidArguments
    case .resourceLimitExceeded: reason = .resourceLimitExceeded
    }
    self.init(reason: reason, format: String(describing: rejection.format))
  }
}
