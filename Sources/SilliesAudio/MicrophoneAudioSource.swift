import AVFoundation
import CoreAudio
import CoreMedia

/// Read-only capture from a built-in microphone where present. Never changes the system input,
/// output, device format, volume, mute state, or voice-processing settings of another app.
final class MicrophoneAudioSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  typealias Receiver = AudioCaptureInputQueue.Receiver
  private let queue = DispatchQueue(label: "app.sillies.microphone", qos: .userInitiated)
  private let outputQueue = DispatchQueue(
    label: "app.sillies.microphone.samples", qos: .userInitiated)
  private let session = AVCaptureSession()
  private let receive: Receiver
  private let failure: @Sendable (String) -> Void
  private var observers: [NSObjectProtocol] = []
  private var stopped = false

  init(receive: @escaping Receiver, failure: @escaping @Sendable (String) -> Void) {
    self.receive = receive
    self.failure = failure
  }

  func start() async throws -> String {
    guard await AVCaptureDevice.requestAccess(for: .audio) else {
      throw AudioCaptureFailure.unavailable(
        "Microphone permission needed. Enable Sillies in System Settings → Privacy & Security → Microphone."
      )
    }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async { [self] in
        do {
          guard !stopped else { throw CancellationError() }
          let name = try configure()
          observeFailures()
          session.startRunning()
          guard session.isRunning else {
            throw AudioCaptureFailure.unavailable(
              "The microphone could not start. Check that it is connected.")
          }
          continuation.resume(returning: name)
        } catch { continuation.resume(throwing: error) }
      }
    }
  }

  private func configure() throws -> String {
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

  private func observeFailures() {
    for name in [
      AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification,
    ] {
      observers.append(
        NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) {
          [weak self] _ in
          self?.failure(
            "Microphone capture was interrupted. Check the input and start a new session.")
        })
    }
  }

  func stop(completion: @escaping @Sendable () -> Void = {}) {
    queue.async { [self] in
      stopped = true
      for observer in observers { NotificationCenter.default.removeObserver(observer) }
      observers.removeAll()
      session.stopRunning()
      completion()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard
      let packet = AudioCaptureInputQueue.Packet(
        sample: sampleBuffer, source: .microphone, sourceClock: session.synchronizationClock)
    else { return }
    receive(packet)
  }
}
