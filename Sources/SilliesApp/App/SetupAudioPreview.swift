import Foundation
import Observation
import SilliesAudio
import SilliesChat
import SilliesCore

/// Explicit, bounded device trials. No transcript or conversation is persisted.
@MainActor @Observable final class SetupAudioPreview {
  enum Phase { case idle, microphone, voice, stopping }
  private static let microphoneLimit: Duration = .seconds(10)
  private static let maximumPreviewCharacters = 240
  private(set) var phase = Phase.idle
  private(set) var level = 0.0
  private(set) var transcript = ""
  private(set) var failure: String?
  private(set) var heardVoice = false
  private(set) var voiceAttribution: ModelAttribution?
  @ObservationIgnored private var microphone: ChatMicrophone?
  @ObservationIgnored private var speech: (any ChatSpeechOutput)?
  @ObservationIgnored private var operation: Task<Void, Never>?
  @ObservationIgnored private var pendingStops = 0
  @ObservationIgnored private var finishWaiters: [@MainActor () -> Void] = []
  @ObservationIgnored private var generation = UUID()
  private let isBusy: @MainActor () -> Bool

  init(isBusy: @escaping @MainActor () -> Bool) { self.isBusy = isBusy }

  func testMicrophone(services: ChatServices, language: String) {
    guard begin(.microphone) else { return }
    let token = generation
    let microphone = ChatMicrophone(services: services)
    self.microphone = microphone
    transcript = ""
    microphone.start(language: language) { [weak self] update in
      guard let self, self.generation == token else { return }
      switch update {
      case .transcript(let text, let level, _):
        self.transcript = text
        self.level = min(1, max(0, level))
      case .failed(let failure), .transcriptionStopped(let failure):
        self.failure = failure.message
        self.stop()
      default: break
      }
    }
    operation = Task { [weak self] in
      do { try await Task.sleep(for: Self.microphoneLimit) } catch { return }
      guard let self, self.generation == token else { return }
      self.stop()
    }
  }

  func testVoice(services: ChatServices, profile: CharacterChatProfile, text: String) {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, begin(.voice) else {
      return
    }
    let token = generation
    speech = services.speech
    heardVoice = false
    operation = Task { [weak self] in
      do {
        let attribution = await services.speech.modelAttribution()
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.voiceAttribution = attribution
        let notice = try await services.speech.speak(
          .init(
            id: token, text: String(text.prefix(Self.maximumPreviewCharacters)), profile: profile),
          receive: { [weak self] update in
            guard case .attribution(let attribution) = update else { return }
            services.deliver { [weak self] in
              guard let self, self.generation == token else { return }
              self.voiceAttribution = attribution
            }
          })
        guard self.generation == token, !Task.isCancelled else { return }
        self.failure = notice
        self.heardVoice = notice == nil
        self.stop()
      } catch is CancellationError {
        guard let self, self.generation == token else { return }
        self.stop()
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.failure = error.localizedDescription
        self.stop()
      }
    }
  }

  private func begin(_ phase: Phase) -> Bool {
    guard self.phase == .idle else { return false }
    guard !isBusy() else {
      failure = String(localized: "Finish the active session before trying audio.")
      return false
    }
    generation = UUID()
    failure = nil
    level = 0
    voiceAttribution = nil
    self.phase = phase
    return true
  }

  func stop() {
    guard phase != .stopping, phase != .idle else { return }
    let previous = generation
    generation = UUID()
    let token = generation
    let operation = operation
    let microphone = microphone
    let speech = speech
    self.speech = nil
    self.operation = nil
    operation?.cancel()
    phase = .stopping
    level = 0
    pendingStops = (microphone == nil ? 0 : 1) + (speech == nil ? 0 : 1)
    if let microphone {
      microphone.finish { [weak self] result in
        guard let self, self.generation == token else { return }
        if let result {
          let words = result.plainText.isEmpty ? result.transcript : result.plainText
          if !words.isEmpty { self.transcript = words }
          if let failure = result.failure { self.failure = failure.message }
        }
        self.microphone = nil
        self.pendingStops -= 1
        self.completeStop()
      }
    }
    if let speech {
      Task.detached { [weak self] in
        await speech.stop(id: previous)
        MainRunLoopDelivery.perform { [weak self] in
          guard let self, self.generation == token else { return }
          self.pendingStops -= 1
          self.completeStop()
        }
      }
    }
    completeStop()
  }

  func finish() async {
    await withCheckedContinuation { continuation in
      finish { continuation.resume() }
    }
  }

  func finish(_ completion: @escaping @MainActor () -> Void) {
    finishWaiters.append(completion)
    stop()
    if phase == .idle { completeStop() }
  }

  private func completeStop() {
    guard pendingStops == 0, phase == .stopping || phase == .idle else { return }
    phase = .idle
    let waiters = finishWaiters
    finishWaiters.removeAll()
    for completion in waiters { completion() }
  }
}
