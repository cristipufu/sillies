import AVFoundation
import Foundation

/// Serial-queue owner of the recognizers for one language. Draining is shared by switch and finish.
final class SpeechChannelGroup: Sendable {
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
  private final class State {
    var completions: [(String?) -> Void] = []
    var unfinishedSources: Set<SessionAudioSource>?
    var deadline: DispatchWorkItem?
    var completed = false
    var notice: String?

  }
  private let storage: SerialQueueStorage<State>

  init(
    id: UUID, channels: [SessionAudioSource: any LocalSpeechChannel], queue: DispatchQueue,
    timeouts: Timeouts = .init()
  ) {
    storage = SerialQueueStorage(queue: queue, makeValue: State.init)
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
    storage.withValue { state in
      dispatchPrecondition(condition: .onQueue(queue))
      if state.completed {
        completion(state.notice)
        return
      }
      state.completions.append(completion)
      guard state.unfinishedSources == nil else { return }
      state.unfinishedSources = Set(channels.keys)
      if channels.isEmpty {
        complete()
        return
      }
      for (source, channel) in channels {
        channel.finish { [weak self, queue] in
          queue.async { [weak self] in self?.channelFinished(source) }
        }
      }
      let work = DispatchWorkItem { [weak self] in self?.timedOut() }
      state.deadline = work
      queue.asyncAfter(deadline: .now() + timeouts.duration(for: reason), execute: work)
    }
  }

  func cancel() {
    dispatchPrecondition(condition: .onQueue(queue))
    cancelChannels()
    complete()
  }

  private func timedOut() {
    storage.withValue { state in
      guard !state.completed else { return }
      state.notice = "Speech finalization took too long. The latest available text was preserved."
      cancelChannels()
      complete()
    }
  }

  private func channelFinished(_ source: SessionAudioSource) {
    storage.withValue { state in
      dispatchPrecondition(condition: .onQueue(queue))
      guard !state.completed, state.unfinishedSources?.remove(source) != nil else { return }
      if state.unfinishedSources?.isEmpty == true { complete() }
    }
  }

  private func cancelChannels() { for channel in channels.values { channel.cancel() } }

  private func complete() {
    storage.withValue { state in
      guard !state.completed else { return }
      state.completed = true
      state.deadline?.cancel()
      state.deadline = nil
      let callbacks = state.completions
      state.completions.removeAll()
      for callback in callbacks { callback(state.notice) }
    }
  }
}
