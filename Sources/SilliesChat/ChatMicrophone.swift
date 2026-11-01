import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech

/// Joins utterance callbacks and device teardown through the injected run-loop delivery.
@MainActor final class ChatMicrophone {
  private let services: ChatServices
  private var capture: (any ConversationCapture)?
  private var delivery: AudioSessionUpdateDelivery?
  private var preparation: Task<Void, Never>?
  private var generation = UUID()
  private var isFinalizing = false
  private var pendingTurns: Set<UUID> = []
  private var deviceFinished = false
  private var finalResult: AudioCaptureResult?
  private var finishWaiters: [@MainActor (AudioCaptureResult?) -> Void] = []

  init(services: ChatServices) { self.services = services }

  func start(language: String, receive: @escaping @MainActor (AudioCaptureUpdate) -> Void) {
    guard capture == nil, preparation == nil, !isFinalizing else { return }
    let token = UUID()
    generation = token
    preparation = Task { [weak self, services] in
      do {
        let catalog = try await services.loadLanguages()
        try Task.checkCancellation()
        guard let self, self.generation == token else { return }
        guard
          let selected = catalog.installedLanguage(matching: language)
            ?? catalog.installed.first(where: \.isAutomatic)
        else {
          throw SessionFailure(
            category: .transcription,
            message:
              String(
                localized:
                  "This speech model cannot recognize the selected language. Choose another in Settings → Speech & Meetings."
              )
          )
        }
        var configuration = AudioCaptureConfiguration(
          kind: .chat, target: nil, recordingURL: nil, language: selected)
        configuration.model = catalog.model
        configuration.recognitionContext.priority = .interactive
        let delivery = AudioSessionUpdateDelivery(schedule: services.deliver) {
          [weak self] update in
          guard self?.generation == token else { return }
          receive(update)
        }
        self.delivery = delivery
        let capture = services.captureFactory(configuration) { delivery.enqueue($0) }
        self.capture = capture
        self.preparation = nil
        capture.start()
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.preparation = nil
        receive(.failed(SessionFailure(error, category: .transcription)))
      }
    }
  }

  func finishTurn(_ completion: @escaping @MainActor (AudioCaptureResult?) -> Void) {
    guard let capture else {
      completion(nil)
      return
    }
    let token = generation
    let turn = UUID()
    pendingTurns.insert(turn)
    let deliver = services.deliver
    capture.finishTurn { [weak self] result in
      deliver { [weak self] in
        guard let self, self.generation == token, self.pendingTurns.remove(turn) != nil else {
          return
        }
        completion(result)
        self.completeFinishIfReady()
      }
    }
  }

  func finish(_ completion: @escaping @MainActor (AudioCaptureResult?) -> Void) {
    finishWaiters.append(completion)
    guard !isFinalizing else { return }
    isFinalizing = true
    deviceFinished = false
    finalResult = nil
    preparation?.cancel()
    preparation = nil
    delivery?.stop()
    delivery = nil
    guard let capture else {
      deviceFinished = true
      completeFinishIfReady()
      return
    }
    self.capture = nil
    let token = generation
    let deliver = services.deliver
    capture.finish { [weak self] result in
      deliver { [weak self] in
        guard let self, self.isFinalizing, !self.deviceFinished, self.generation == token else {
          return
        }
        self.finalResult = result
        self.deviceFinished = true
        self.completeFinishIfReady()
      }
    }
  }

  private func completeFinishIfReady() {
    guard isFinalizing, deviceFinished, pendingTurns.isEmpty else { return }
    isFinalizing = false
    generation = UUID()
    let result = finalResult
    finalResult = nil
    let waiters = finishWaiters
    finishWaiters.removeAll()
    for waiter in waiters { waiter(result) }
  }
}
