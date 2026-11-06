import Foundation
import Observation
import SilliesCore

/// One bounded page of headers. A new query immediately retires the previous selectable results.
@MainActor @Observable final class ChatVaultPickerModel {
  var query = "" {
    didSet {
      guard query != oldValue else { return }
      generation = UUID()
      records = []
      failure = nil
      isLoading = false
    }
  }
  private(set) var records: [SessionRecordHeader] = []
  private(set) var isLoading = false
  private(set) var failure: String?
  private var generation = UUID()
  private let load: (String) async throws -> [SessionRecordHeader]
  private static let searchDelay: Duration = .milliseconds(200)

  init(load: @escaping (String) async throws -> [SessionRecordHeader]) { self.load = load }

  convenience init(store: SessionVaultStore) {
    self.init { query in
      try await store.page(.init(search: .init(kind: nil, query: query))).records
    }
  }

  func search() async {
    let token = UUID()
    generation = token
    isLoading = true
    let submitted = query
    defer { if generation == token { isLoading = false } }
    do {
      if !submitted.isEmpty { try await Task.sleep(for: Self.searchDelay) }
      let records = try await load(submitted)
      try Task.checkCancellation()
      guard generation == token else { return }
      self.records = records
      failure = nil
    } catch is CancellationError {
    } catch {
      guard generation == token else { return }
      failure = error.localizedDescription
    }
  }
}
