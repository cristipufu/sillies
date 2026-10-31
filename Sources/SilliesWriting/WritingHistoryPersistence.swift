import Foundation

package enum WritingHistoryFailure: LocalizedError, Equatable, Sendable {
  case load(String)
  case save(String)

  package var message: String {
    switch self {
    case .load: "Recent writing could not be opened. Keep a copy of your text until retry succeeds."
    case .save: "Recent writing could not be saved. Keep a copy of your text until retry succeeds."
    }
  }
  package var errorDescription: String? { "\(message) \(detail)" }
  package var detail: String {
    switch self {
    case .load(let detail), .save(let detail): detail
    }
  }
}

package enum WritingHistoryPersistence: Equatable, Sendable {
  case loading, saving, saved
  case failed(WritingHistoryFailure)

  package var failure: WritingHistoryFailure? {
    if case .failed(let failure) = self { failure } else { nil }
  }
}
