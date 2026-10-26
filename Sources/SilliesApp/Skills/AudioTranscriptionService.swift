import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import SilliesCore
@preconcurrency import Speech

/// Captures isolated application/window audio via ScreenCaptureKit and performs live on-device
/// Speech-to-Text transcription using the Speech framework.
final class AudioTranscriptionService: NSObject, @unchecked Sendable {
  struct Update: Sendable {
    let transcript: String?
    let audioLevel: Double
    let statusMessage: String
  }

  private let target: WindowTargetCandidate
  private let onUpdate: @Sendable (Update) -> Void
  private let audioQueue = DispatchQueue(label: "app.sillies.audio-capture", qos: .userInitiated)
  private let speechQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.name = "app.sillies.speech-recognition"
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInitiated
    return queue
  }()
  private let lock = NSLock()
  private var stream: SCStream?
  private var recognizer: SFSpeechRecognizer?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var latestTranscript = ""
  private var committedTranscript = ""
  private var lastLevelEmitTime: TimeInterval = 0
  private var lastEmittedLevel: Double = -1
  private var lastEmittedStatus = ""
  private var isStopped = false

  init(target: WindowTargetCandidate, onUpdate: @escaping @Sendable (Update) -> Void) {
    self.target = target
    self.onUpdate = onUpdate
    speechQueue.underlyingQueue = audioQueue
    super.init()
  }

  func start() async {
    let speechAuthorized = await requestSpeechAuthorization()
    if speechAuthorized {
      configureSpeechRecognition()
    }
    do {
      let content = try await SCShareableContent.excludingDesktopWindows(
        false, onScreenWindowsOnly: false)
      let filter: SCContentFilter
      if let display = content.displays.first,
        let app = content.applications.first(where: { $0.processID == target.processID })
      {
        filter = SCContentFilter(
          display: display, including: [app], exceptingWindows: [])
      } else if let scWindow = content.windows.first(where: { $0.windowID == target.windowID }) {
        filter = SCContentFilter(desktopIndependentWindow: scWindow)
      } else {
        onUpdate(
          Update(
            transcript: "", audioLevel: 0,
            statusMessage: "Target window unavailable for audio capture"))
        return
      }

      let config = SCStreamConfiguration()
      config.capturesAudio = true
      config.excludesCurrentProcessAudio = true
      config.sampleRate = 48_000
      config.channelCount = 1
      config.width = 2
      config.height = 2
      config.minimumFrameInterval = CMTime(value: 1, timescale: 1)

      let scStream = SCStream(filter: filter, configuration: config, delegate: nil)
      try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
      try await scStream.startCapture()

      let wasStopped: Bool = lock.withLock {
        if isStopped { return true }
        stream = scStream
        return false
      }
      if wasStopped {
        try? await scStream.stopCapture()
        return
      }

      let initialStatus =
        speechAuthorized
        ? "Listening to \(target.appName)…"
        : "Monitoring \(target.appName) audio (enable Speech Recognition for live text)"
      onUpdate(Update(transcript: "", audioLevel: 0, statusMessage: initialStatus))
    } catch {
      onUpdate(
        Update(
          transcript: "",
          audioLevel: 0,
          statusMessage:
            "Grant Screen & System Audio Recording in System Settings to transcribe \(target.appName)."
        ))
    }
  }

  func stop() -> String {
    lock.lock()
    guard !isStopped else {
      let existing = combinedTranscriptLocked()
      lock.unlock()
      return existing
    }
    isStopped = true
    let activeStream = stream
    stream = nil
    let request = recognitionRequest
    recognitionRequest = nil
    let task = recognitionTask
    recognitionTask = nil
    let finalTranscript = combinedTranscriptLocked()
    lock.unlock()

    if request != nil || task != nil {
      audioQueue.async {
        request?.endAudio()
        task?.cancel()
      }
    }
    if let activeStream {
      Task {
        try? await activeStream.stopCapture()
      }
    }
    return finalTranscript
  }

  private func requestSpeechAuthorization() async -> Bool {
    let current = SFSpeechRecognizer.authorizationStatus()
    if current == .authorized { return true }
    if current == .denied || current == .restricted { return false }
    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  private func configureSpeechRecognition() {
    guard let speechRecognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(),
      speechRecognizer.isAvailable
    else { return }
    speechRecognizer.queue = speechQueue

    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    if speechRecognizer.supportsOnDeviceRecognition {
      request.requiresOnDeviceRecognition = true
    }

    lock.lock()
    recognizer = speechRecognizer
    recognitionRequest = request
    recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        let formatted = result.bestTranscription.formattedString
        self.lock.lock()
        if result.isFinal {
          if !formatted.isEmpty {
            self.committedTranscript =
              self.committedTranscript.isEmpty
              ? formatted : "\(self.committedTranscript)\n\(formatted)"
            self.latestTranscript = ""
          }
        } else {
          self.latestTranscript = formatted
        }
        let fullText = self.combinedTranscriptLocked()
        let snippet = self.latestTailSnippetLocked()
        let message = snippet.isEmpty ? "Listening to \(self.target.appName)…" : snippet
        self.lastEmittedStatus = message
        self.lastEmittedLevel = 0.25
        self.lock.unlock()

        self.onUpdate(
          Update(
            transcript: fullText,
            audioLevel: 0.25,
            statusMessage: message))
      }
      if error != nil {
        self.restartSpeechTaskIfNeeded()
      }
    }
    lock.unlock()
  }

  private func restartSpeechTaskIfNeeded() {
    lock.lock()
    guard !isStopped, let speechRecognizer = recognizer, speechRecognizer.isAvailable else {
      lock.unlock()
      return
    }
    if !latestTranscript.isEmpty {
      committedTranscript =
        committedTranscript.isEmpty
        ? latestTranscript : "\(committedTranscript)\n\(latestTranscript)"
      latestTranscript = ""
    }
    lock.unlock()
    configureSpeechRecognition()
  }

  private func combinedTranscriptLocked() -> String {
    if committedTranscript.isEmpty { return latestTranscript }
    if latestTranscript.isEmpty { return committedTranscript }
    return "\(committedTranscript) \(latestTranscript)"
  }

  private func latestTailSnippetLocked() -> String {
    let source = !latestTranscript.isEmpty ? latestTranscript : committedTranscript
    return Self.tailSnippet(from: String(source.suffix(120)))
  }

  private static func tailSnippet(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return "" }
    if trimmed.count <= 56 { return "“\(trimmed)”" }
    return "“…\(trimmed.suffix(54))”"
  }
}

extension AudioTranscriptionService: SCStreamOutput {
  func stream(
    _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
    of outputType: SCStreamOutputType
  ) {
    guard outputType == .audio, sampleBuffer.isValid else { return }
    guard let pcmBuffer = Self.makePCMBuffer(from: sampleBuffer) else { return }

    lock.lock()
    let activeRequest = recognitionRequest
    let now = ProcessInfo.processInfo.systemUptime
    let shouldEmitLevel = now - lastLevelEmitTime >= 0.08
    if shouldEmitLevel { lastLevelEmitTime = now }
    let snippet = shouldEmitLevel ? latestTailSnippetLocked() : ""
    lock.unlock()

    activeRequest?.append(pcmBuffer)

    if shouldEmitLevel {
      let rms = Self.computeRMSLevel(from: pcmBuffer)
      let message =
        !snippet.isEmpty
        ? snippet
        : (rms > 0.04
          ? "Capturing audio from \(target.appName)…" : "Listening to \(target.appName)…")
      let shouldNotify: Bool = lock.withLock {
        guard message != lastEmittedStatus || abs(rms - lastEmittedLevel) >= 0.025 else {
          return false
        }
        lastEmittedStatus = message
        lastEmittedLevel = rms
        return true
      }
      if shouldNotify {
        onUpdate(Update(transcript: nil, audioLevel: rms, statusMessage: message))
      }
    }
  }

  private static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let formatDescription = sampleBuffer.formatDescription else { return nil }
    let audioFormat = AVAudioFormat(cmAudioFormatDescription: formatDescription)
    let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
    guard frameCount > 0,
      let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: frameCount)
    else { return nil }
    pcmBuffer.frameLength = frameCount
    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer, at: 0, frameCount: Int32(frameCount), into: pcmBuffer.mutableAudioBufferList)
    return status == noErr ? pcmBuffer : nil
  }

  private static func computeRMSLevel(from buffer: AVAudioPCMBuffer) -> Double {
    guard let channelData = buffer.floatChannelData else { return 0 }
    let count = Int(buffer.frameLength)
    guard count > 0 else { return 0 }
    let samples = channelData[0]
    var sumSquares: Float = 0
    let strideStep = max(1, count / 128)
    var sampled = 0
    var index = 0
    while index < count {
      let sample = samples[index]
      sumSquares += sample * sample
      sampled += 1
      index += strideStep
    }
    guard sampled > 0 else { return 0 }
    let rms = sqrt(sumSquares / Float(sampled))
    return min(max(Double(rms) * 6.0, 0), 1)
  }
}
