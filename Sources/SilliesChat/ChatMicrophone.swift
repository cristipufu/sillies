import Foundation
import SilliesAudio
import SilliesCore
import SilliesSpeech

/// An explicit microphone turn. Capture teardown completes through the injected run-loop delivery.
@MainActor final class ChatMicrophone {
  private static let maximumTurnDuration: Duration = .seconds(120)
  private let services: ChatServices
  private var capture: (any SessionAudioCapture)?
  private var delivery: AudioSessionUpdateDelivery?
  private var preparation: Task<Void, Never>?
  private var deadline: Task<Void, Never>?
  private var generation = UUID()
  private var isFinalizing = false
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
              "This speech model cannot recognize the selected language. Choose another in Settings → Speech & Meetings."
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
        self.deadline = Task { [weak self] in
          do { try await Task.sleep(for: Self.maximumTurnDuration) } catch { return }
          guard self?.generation == token else { return }
          receive(
            .failed(
              .init(
                category: .captureInterrupted,
                message:
                  "Microphone turn reached two minutes. Your words are kept; send them or start another turn."
              )))
        }
      } catch {
        guard let self, self.generation == token, !Task.isCancelled else { return }
        self.preparation = nil
        receive(.failed(SessionFailure(error, category: .transcription)))
      }
    }
  }

  func finish(_ completion: @escaping @MainActor (AudioCaptureResult?) -> Void) {
    finishWaiters.append(completion)
    guard !isFinalizing else { return }
    generation = UUID()
    preparation?.cancel()
    preparation = nil
    deadline?.cancel()
    deadline = nil
    delivery?.stop()
    delivery = nil
    guard let capture else {
      completeFinish(nil)
      return
    }
    self.capture = nil
    isFinalizing = true
    let token = generation
    let deliver = services.deliver
    capture.finish { [weak self] result in
      deliver { [weak self] in
        guard let self, self.isFinalizing, self.generation == token else { return }
        self.isFinalizing = false
        self.completeFinish(result)
      }
    }
  }

  private func completeFinish(_ result: AudioCaptureResult?) {
    let waiters = finishWaiters
    finishWaiters.removeAll()
    for waiter in waiters { waiter(result) }
  }
}
