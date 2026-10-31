import Foundation
import Observation
import SilliesCore

@MainActor @Observable final class SelectionCommandCoordinator {
  private static let deadline: Duration = .seconds(8)
  @MainActor struct Services {
    var insertion: any TextInserting = TextInsertionService()
    var cleanup = BoundedTextCleanup()
    var currentApplication: () -> FrontmostApplication? = { .current }
    var transform: @Sendable (String, LocalTextOperation) async throws -> String = {
      try await LocalReasoningService.shared.transform($0, operation: $1)
    }
  }
  private(set) var isWorking = false
  private(set) var status = ""
  private(set) var result: WritingResult?
  var activityChanged: (Bool) -> Void = { _ in }
  var changed: () -> Void = {}
  private let insertion: any TextInserting
  private let cleanup: BoundedTextCleanup
  private let history: WritingHistory
  private let services: Services
  private var work: Task<Void, Never>?
  private var generation = UUID()
  private var destination: TextDestination?

  init(history: WritingHistory, services: Services = .init()) {
    self.history = history
    self.services = services
    cleanup = services.cleanup
    insertion = services.insertion
  }

  func start(_ operation: LocalTextOperation) {
    guard !isWorking, let application = services.currentApplication() else { return }
    generation = UUID()
    let token = generation
    isWorking = true
    result = nil
    status = "Reading your selection…"
    activityChanged(true)
    changed()
    work = Task { [weak self] in
      await self?.execute(operation, application: application, token: token)
    }
  }

  private func execute(
    _ operation: LocalTextOperation, application: FrontmostApplication, token: UUID
  ) async {
    do {
      let destination = try await insertion.capture(application)
      guard generation == token, !Task.isCancelled else {
        await insertion.release(destination)
        return
      }
      self.destination = destination
      guard !destination.selection.isEmpty else { throw SelectionCommandError.noSelection }
      guard destination.selection.count <= LocalTextTransform.maximumCharacters else {
        throw LocalTextTransformError.tooLong
      }
      status = "Writing on this Mac…"
      changed()
      let output = await cleanup.perform(destination.selection, deadline: Self.deadline) {
        [services] in
        try await services.transform($0, operation)
      }
      try Task.checkCancellation()
      guard generation == token else { return }
      let text = try acceptedText(output)
      var result = WritingResult(
        originalText: destination.selection, text: text, applicationName: application.name)
      history.save(result)
      let message: String
      do {
        try await insertion.insert(text, into: destination)
        result.delivery = .inserted
        message = "Selection updated in \(application.name)"
      } catch {
        result.delivery = .needsPaste
        result.notice = error.localizedDescription
        message = "Your edited text is ready to copy"
      }
      history.save(result)
      guard generation == token else { return }
      status = message
      self.result = result
    } catch {
      if generation == token, !Task.isCancelled { status = error.localizedDescription }
    }
    guard generation == token else { return }
    finish()
  }

  private func acceptedText(_ output: BoundedTextCleanup.Outcome) throws -> String {
    switch output {
    case .completed(let text):
      guard !text.isEmpty else { throw SelectionCommandError.empty }
      return text
    case .failed(let message): throw SelectionCommandError.failed(message)
    case .timedOut:
      throw SelectionCommandError.failed(
        "Local writing took too long. Your selection was left intact.")
    case .busy:
      throw SelectionCommandError.failed(
        "The local model is still finishing another request. Please try again.")
    case .canceled: throw CancellationError()
    }
  }
  func cancel() {
    generation = UUID()
    work?.cancel()
    work = nil
    status = "Writing canceled"
    finish()
  }
  private func finish() {
    isWorking = false
    if let destination { Task { [insertion] in await insertion.release(destination) } }
    destination = nil
    activityChanged(false)
    changed()
  }
}

private enum SelectionCommandError: LocalizedError {
  case noSelection, empty
  case failed(String)
  var errorDescription: String? {
    switch self {
    case .noSelection: "Select the text you want to edit first."
    case .empty: "The local model returned no text. Your selection was left intact."
    case .failed(let message): message
    }
  }
}
