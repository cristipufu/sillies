import Foundation
import SilliesChat
import SilliesCore
import SilliesTTS

/// Serial speech output with bounded synthesis requests and hardware backpressure.
actor ChatSpeechPlayer: ChatSpeechOutput {
  private let models: VoiceModelEnvironment
  private let playback: any SpeechPlayback
  private var active: (id: UUID, task: Task<String?, Error>)?
  private var interruptedPlaybackID: UUID?
  private var firstPCMFor: UUID?
  private var pausedID: UUID?

  init(models: VoiceModelEnvironment, playback: any SpeechPlayback) {
    self.models = models
    self.playback = playback
  }

  func availabilityNotice(language: String) async -> String? {
    do {
      guard let manifest = try await models.selectedModel() else {
        return
          String(
            localized:
              "You can chat by typing. Download and choose a voice in Settings → Voices for spoken replies."
          )
      }
      guard try await models.store.isInstalled(manifest) else {
        return String(
          localized: "Download \(manifest.model.name) in Settings → Voices for spoken replies.")
      }
      guard manifest.model.supports(language: language) else {
        return
          String(
            localized:
              "The selected voice does not support this language. You can continue chatting in text."
          )
      }
      return nil
    } catch { return error.localizedDescription }
  }

  func speak(
    _ request: ChatSpeechRequest,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    let text = SpeechTextStream()
    for phrase in SpokenTextChunks.split(
      request.text, maximumCharacters: SpeechSynthesisRequest.maximumTextCharacters)
    {
      try await text.append(phrase)
    }
    await text.finish()
    return try await speakStream(request, text: text, receive: receive)
  }

  func speakStream(
    _ request: ChatSpeechRequest, text: SpeechTextStream,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    if let previous = active, previous.task.isCancelled {
      _ = await previous.task.result
      if active?.id == previous.id { active = nil }
    }
    try Task.checkCancellation()
    guard active == nil else { throw TTSError.busy }
    if pausedID != request.id { pausedID = nil }
    let task = Task { try await self.perform(request, text: text, receive: receive) }
    active = (request.id, task)
    defer {
      if active?.id == request.id { active = nil }
      if interruptedPlaybackID == request.id { interruptedPlaybackID = nil }
      if pausedID == request.id { pausedID = nil }
    }
    return try await withTaskCancellationHandler {
      try await task.value
    } onCancel: {
      task.cancel()
    }
  }

  func stop(id: UUID) async {
    if pausedID == id { pausedID = nil }
    guard let active, active.id == id else { return }
    active.task.cancel()
    await playback.stop(id: id)
    _ = await active.task.result
  }

  func pause(id: UUID) async {
    guard !Task.isCancelled, active == nil || active?.id == id else { return }
    pausedID = id
    await playback.pause(id: id)
  }

  func resume(id: UUID) async {
    guard !Task.isCancelled, pausedID == id else { return }
    pausedID = nil
    await playback.resume(id: id)
  }

  private func perform(
    _ request: ChatSpeechRequest, text: SpeechTextStream,
    receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws -> String? {
    guard let manifest = try await models.selectedModel() else {
      return String(
        localized:
          "Text replies are ready. Add a voice in Settings → Voices to hear your companion.")
    }
    let language = request.profile.languageIdentifier
    guard manifest.model.supports(language: language) else {
      return
        String(
          localized:
            "This voice model does not speak the selected language. Your conversation continues in text."
        )
    }
    let preferred = request.profile.preferredVoices[manifest.model.providerID]
    let voices = manifest.model.voices.filter { $0.supports(language: language) }
    guard let voice = voices.first(where: { $0.id == preferred }) ?? voices.first else {
      throw TTSError.unsupportedVoice
    }
    try Task.checkCancellation()
    if let lifetime = request.lifetime { await models.retain(for: lifetime) }
    guard try await text.waitForTextStart() else { return nil }
    receive(.milestone(.preparationStarted))
    firstPCMFor = nil
    await playback.start(id: request.id) { [weak self] update in
      receive(update)
      if case .interrupted = update {
        Task { await self?.playbackInterrupted(id: request.id) }
      }
    }
    if pausedID == request.id { await playback.pause(id: request.id) }
    do {
      async let voiceReady = models.prepareVoiceIfPossible(
        .init(id: voice.id, language: language), using: manifest, conversationID: request.id)
      if let sampleRate = manifest.model.outputSampleRate {
        try await playback.prepare(sampleRate: sampleRate, id: request.id)
      }
      if try await voiceReady { receive(.milestone(.voicePrepared)) }
      while let chunk = try await text.next() {
        try Task.checkCancellation()
        try await models.synthesize(
          .init(text: chunk, voiceID: voice.id, language: language, conversationID: request.id),
          using: manifest
        ) { audio in try await self.enqueue(audio, id: request.id, receive: receive) }
        try await playback.markUtterance(chunk, id: request.id)
      }
      try await playback.finish(id: request.id)
      return nil
    } catch {
      await playback.stop(id: request.id)
      if interruptedPlaybackID == request.id { throw TTSError.interrupted }
      throw error
    }
  }

  private func enqueue(
    _ audio: SynthesizedAudio, id: UUID, receive: @escaping @Sendable (SpeechPlaybackUpdate) -> Void
  ) async throws {
    if firstPCMFor != id {
      firstPCMFor = id
      receive(.milestone(.firstPCM))
    }
    try await playback.enqueue(audio, id: id)
  }

  private func playbackInterrupted(id: UUID) {
    guard active?.id == id else { return }
    interruptedPlaybackID = id
    active?.task.cancel()
  }
}
