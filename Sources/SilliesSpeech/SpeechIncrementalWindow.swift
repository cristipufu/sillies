import Foundation

/// Retains only an audio cursor. Reset at utterance/overlap boundaries, never across sources.
package struct SpeechIncrementalWindow {
  package enum Action { case restart, append }
  package struct Update {
    package let action: Action
    package let samples: [Float]
    package let phase: SpeechWindowPosition.Phase
  }
  private var start: TimeInterval?
  private var consumed = 0
  private var completed = false

  package init() {}

  package mutating func advance(_ request: SpeechWindowRequest) -> Update {
    let position = request.window
    let restart =
      completed || position == nil || start != position?.start
      || request.samples.count < consumed
    let offset = restart ? 0 : consumed
    let phase = position?.phase ?? .complete
    start = position?.start
    consumed = request.samples.count
    completed = phase == .complete
    return Update(
      action: restart ? .restart : .append,
      samples: Array(request.samples.dropFirst(offset)), phase: phase)
  }
}
