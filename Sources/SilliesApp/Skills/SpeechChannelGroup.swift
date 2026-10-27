import Foundation

/// Serial-queue owner of the recognizers for one language. Draining is shared by switch and finish.
final class SpeechChannelGroup {
  enum FinishReason {
    case languageChange, sessionEnd
    var timeout: TimeInterval { self == .languageChange ? 2 : 8 }
  }
  let id: UUID
  let channels: [SessionAudioSource: any LocalSpeechChannel]
  private let queue: DispatchQueue
  private var completions: [(String?) -> Void] = []
  private var remaining: Int?
  private var completed = false
  private var notice: String?

  init(id: UUID, channels: [SessionAudioSource: any LocalSpeechChannel], queue: DispatchQueue) {
    self.id = id
    self.channels = channels
    self.queue = queue
  }

  func finish(reason: FinishReason, completion: @escaping (String?) -> Void) {
    if completed {
      completion(notice)
      return
    }
    completions.append(completion)
    guard remaining == nil else { return }
    remaining = channels.count
    if channels.isEmpty {
      complete()
      return
    }
    for channel in channels.values {
      channel.finish { [weak self, queue] in
        queue.async { [weak self] in self?.channelFinished() }
      }
    }
    queue.asyncAfter(deadline: .now() + reason.timeout) { [weak self] in
      guard let self, !self.completed else { return }
      self.notice = "Speech finalization took too long. The latest available text was preserved."
      self.cancelChannels()
      self.complete()
    }
  }

  func cancel() {
    cancelChannels()
    complete()
  }

  private func channelFinished() {
    guard !completed, let remaining else { return }
    self.remaining = remaining - 1
    if self.remaining == 0 { complete() }
  }

  private func cancelChannels() { for channel in channels.values { channel.cancel() } }

  private func complete() {
    guard !completed else { return }
    completed = true
    let callbacks = completions
    completions.removeAll()
    for callback in callbacks { callback(notice) }
  }
}

// All mutable state and callbacks are confined to the supplied serial queue.
extension SpeechChannelGroup: @unchecked Sendable {}
