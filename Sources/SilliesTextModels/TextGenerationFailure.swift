import Foundation

/// Content-free runtime evidence. A failed generation is not, by itself, a model-quality diagnosis.
package struct TextGenerationFailure: Codable, Sendable, LocalizedError {
  package enum Reason: String, Codable, Sendable {
    case outputTokenLimit, rejectedToolCall, missingCompletion, responseSizeLimit
    case streamMismatch, emptyDelta, emptyResponse
  }
  package struct ToolRejection: Codable, Sendable {
    package enum Reason: String, Codable, Sendable {
      case malformedSyntax, incompleteOutput, missingToolName, undeclaredTool
      case invalidArguments, resourceLimitExceeded
    }
    package let reason: Reason
    package let format: String
    package init(reason: Reason, format: String) {
      self.reason = reason
      self.format = format
    }
  }
  package struct OutputCounts: Codable, Sendable {
    package let responseBytes: Int
    package let reasoningBytes: Int
    package let acceptedToolCalls: Int
    package init(responseBytes: Int, reasoningBytes: Int, acceptedToolCalls: Int) {
      self.responseBytes = responseBytes
      self.reasoningBytes = reasoningBytes
      self.acceptedToolCalls = acceptedToolCalls
    }
  }
  package let reason: Reason
  package let metrics: TextGenerationMetrics?
  package let toolRejection: ToolRejection?
  package let outputCounts: OutputCounts?
  package init(
    reason: Reason, metrics: TextGenerationMetrics? = nil, toolRejection: ToolRejection? = nil,
    outputCounts: OutputCounts? = nil
  ) {
    self.reason = reason
    self.metrics = metrics
    self.toolRejection = toolRejection
    self.outputCounts = outputCounts
  }
  package var errorDescription: String? { TextModelError.invalidResponse.errorDescription }
}
