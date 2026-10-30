import Foundation
import SilliesCore

/// The app owns scheduling; Core's summarizer remains a deterministic synchronous function.
enum SessionSummaryWorker {
  static func summarize(text: String, fallbackContext: String) async -> (
    summary: String, actionItems: [String]
  ) {
    await Task.detached(priority: .userInitiated) {
      dispatchPrecondition(condition: .notOnQueue(.main))
      return SessionSummarizer.summarize(text: text, fallbackContext: fallbackContext)
    }.value
  }
}
