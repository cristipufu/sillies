import AVFoundation
import Foundation

/// Serial-queue owner of the recognizers for one language. Draining is shared by switch and finish.
final class SpeechChannelGroup {
  enum FinishReason {
    case languageChange, sessionEnd
  }
  struct Timeouts: Sendable {
    var languageChange: TimeInterval = 2
    var sessionEnd: TimeInterval = 8
    func duration(for reason: FinishReason) -> TimeInterval {
      switch reason {
      case .languageChange: languageChange
      case .sessionEnd: sessionEnd
      }
    }
  }
  let id: UUID
  private let channels: [SessionAudioSource: any LocalSpeechChannel]
  private let queue: DispatchQueue
  private let timeouts: Timeouts
  private var completions: [(String?) -> Void] = []
  private var unfinishedSources: Set<SessionAudioSource>?
  private var deadline: DispatchWorkItem?
  private var completed = false
  private var notice: String?

  init(
    id: UUID, channels: [SessionAudioSource: any LocalSpeechChannel], queue: DispatchQueue,
    timeouts: Timeouts = .init()
  ) {
    self.id = id
    self.channels = channels
    self.queue = queue
    self.timeouts = timeouts
  }

  func append(_ buffer: AVAudioPCMBuffer, source: SessionAudioSource) {
    dispatchPrecondition(condition: .onQueue(queue))
    channels[source]?.append(buffer)
  }

  func finish(reason: FinishReason, completion: @escaping (String?) -> Void) {
    dispatchPrecondition(condition: .onQueue(queue))
    if completed {
      completion(notice)
      return
    }
    completions.append(completion)
    guard unfinishedSources == nil else { return }
    unfinishedSources = Set(channels.keys)
    if channels.isEmpty {
      complete()
      return
    }
    for (source, channel) in channels {
      channel.finish { [weak self, queue] in
        queue.async { [weak self] in self?.channelFinished(source) }
      }
    }
    let deadline = DispatchWorkItem { [weak self] in
      guard let self, !self.completed else { return }
      self.notice = "Speech finalization took too long. The latest available text was preserved."
      self.cancelChannels()
      self.complete()
    }
    self.deadline = deadline
    queue.asyncAfter(deadline: .now() + timeouts.duration(for: reason), execute: deadline)
  }

  func cancel() {
    dispatchPrecondition(condition: .onQueue(queue))
    cancelChannels()
    complete()
  }

  private func channelFinished(_ source: SessionAudioSource) {
    dispatchPrecondition(condition: .onQueue(queue))
    guard !completed, unfinishedSources?.remove(source) != nil else { return }
    if unfinishedSources?.isEmpty == true { complete() }
  }

  private func cancelChannels() { for channel in channels.values { channel.cancel() } }

  private func complete() {
    guard !completed else { return }
    completed = true
    deadline?.cancel()
    deadline = nil
    let callbacks = completions
    completions.removeAll()
    for callback in callbacks { callback(notice) }
  }
}

// All mutable state and callbacks are confined to the supplied serial queue.
extension SpeechChannelGroup: @unchecked Sendable {}
