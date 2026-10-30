import AVFoundation
import CoreAudio
import CoreMedia
import SilliesCore
import Synchronization

/// Read-only capture from a built-in microphone where present. Never changes the system input,
/// output, device format, volume, mute state, or voice-processing settings of another app.
final class MicrophoneAudioSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  Sendable
{
  typealias Receiver = AudioCaptureInputQueue.Receiver
  private let queue = DispatchQueue(label: "app.sillies.microphone", qos: .userInitiated)
  private let outputQueue = DispatchQueue(
    label: "app.sillies.microphone.samples", qos: .userInitiated)
  private final class State {
    let session = AVCaptureSession()
    var observers: [NSObjectProtocol] = []
    var stopped = false
  }
  private let storage: SerialQueueStorage<State>
  private let sourceClock = Mutex<CMClock?>(nil)
  private let receive: Receiver
  private let failure: @Sendable (SessionFailure) -> Void

  init(receive: @escaping Receiver, failure: @escaping @Sendable (SessionFailure) -> Void) {
    storage = SerialQueueStorage(queue: queue, makeValue: State.init)
    self.receive = receive
    self.failure = failure
  }

  func start() async throws -> String {
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw SessionFailure.permissionDenied(.openMicrophoneSettings)
    }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          let name = try storage.withValue { state in
            guard !state.stopped else { throw CancellationError() }
            let name = try configure(state.session)
            observeFailures(state)
            state.session.startRunning()
            guard state.session.isRunning else {
              throw AudioCaptureFailure.unavailable(
                "The microphone could not start. Check that it is connected.")
            }
            sourceClock.withLock { $0 = state.session.synchronizationClock }
            return name
          }
          continuation.resume(returning: name)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func configure(_ session: AVCaptureSession) throws -> String {
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
    ).devices
    let builtIn = devices.first {
      UInt32(bitPattern: $0.transportType) == kAudioDeviceTransportTypeBuiltIn
    }
    guard let device = builtIn ?? AVCaptureDevice.default(for: .audio) else {
      throw AudioCaptureFailure.unavailable("No microphone is available.")
    }
    let input = try AVCaptureDeviceInput(device: device)
    let output = AVCaptureAudioDataOutput()
    output.setSampleBufferDelegate(self, queue: outputQueue)
    session.beginConfiguration()
    defer { session.commitConfiguration() }
    guard session.canAddInput(input), session.canAddOutput(output) else {
      throw AudioCaptureFailure.unavailable(
        "The microphone cannot be shared right now. Your meeting settings were not changed.")
    }
    session.addInput(input)
    session.addOutput(output)
    return device.localizedName
  }

  private func observeFailures(_ state: State) {
    for name in [
      AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
    ] {
      state.observers.append(
        NotificationCenter.default.addObserver(forName: name, object: state.session, queue: nil) {
          [weak self] _ in
          self?.failure(
            SessionFailure(
              category: .captureInterrupted,
              message:
                "Microphone capture was interrupted. Check the input and start a new session."))
        })
    }
  }

  func stop(completion: @escaping @Sendable () -> Void = {}) {
    queue.async { [self] in
      storage.withValue { state in
        state.stopped = true
        for observer in state.observers { NotificationCenter.default.removeObserver(observer) }
        state.observers.removeAll()
        state.session.stopRunning()
      }
      completion()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard
      let packet = AudioCaptureInputQueue.Packet(
        sample: sampleBuffer, source: .microphone, sourceClock: sourceClock.withLock { $0 })
    else { return }
    receive(packet)
  }
}
