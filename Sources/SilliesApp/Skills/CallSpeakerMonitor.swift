import AppKit
import Foundation
import SilliesAudio
import SilliesCore

/// Reuses the shared skill tick. Cancellation and generations own every off-main read.
@MainActor
final class CallSpeakerMonitor {
  @MainActor struct Environment {
    let isPointerDown: () -> Bool
    let primaryScreenTop: () -> Double
    static let native = Self(
      isPointerDown: { NSEvent.pressedMouseButtons != 0 },
      primaryScreenTop: { Double(NSScreen.screens.first?.frame.maxY ?? 0) })
  }
  private let reader: any CallSpeakerReading
  private let environment: Environment
  private var polling = CallSpeakerPolling()
  private var task: Task<Void, Never>?
  private var generation = UUID()
  private var isSuspended = true
  private var isStopped = false
  init(reader: any CallSpeakerReading, environment: Environment = .native) {
    self.reader = reader
    self.environment = environment
  }

  func tick(_ context: SkillTickContext, capture: any SessionAudioCapture) {
    guard !isStopped, let target = context.target else { return }
    let settled = polling.isSettled(frame: target.frame, at: context.now)
    guard context.snapshot?.visibility == .visible,
      context.snapshot?.ownerPID == target.processID,
      !environment.isPointerDown(), settled
    else {
      if !isSuspended {
        capture.observeCallSpeakers(
          .init(
            source: .init(processID: target.processID, windowID: target.windowID),
            capturedAt: context.now, availability: .unavailable))
      }
      cancelRead()
      isSuspended = true
      return
    }
    isSuspended = false
    guard task == nil, polling.takeRead(at: context.now) else { return }
    let request = CallSpeakerReadRequest(
      target: target, primaryScreenTop: environment.primaryScreenTop(),
      verifiedTitle: context.snapshot?.title)
    let generation = generation
    task = Task { [weak self, reader] in
      let observation = await reader.read(request)
      guard !Task.isCancelled, let self, self.generation == generation, !self.isStopped else {
        return
      }
      self.task = nil
      guard observation.source.processID == target.processID,
        observation.source.windowID == target.windowID
      else { return }
      capture.observeCallSpeakers(observation)
      if observation.availability == .unsupported { self.stop() }
    }
  }

  func suspend() {
    cancelRead()
    polling.suspend()
    isSuspended = true
  }
  private func cancelRead() {
    generation = UUID()
    task?.cancel()
    task = nil
  }
  func stop() {
    guard !isStopped else { return }
    isStopped = true
    suspend()
    Task.detached(priority: .utility) { [reader] in await reader.stop() }
  }
}
