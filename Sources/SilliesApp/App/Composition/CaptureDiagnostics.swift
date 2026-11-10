import Foundation
import SilliesAudio
import SilliesCore
import SilliesDiagnostics
import SilliesSpeech

enum CaptureDiagnostics {
  static func record(
    _ update: AudioCaptureLifecycleEvent, operation: UUID, sink: DiagnosticSink
  ) {
    var event = DiagnosticEvent(.capture, .phaseChanged, operation: operation)
    switch update {
    case .capturing:
      event.phase = .listening
    case .finishing(let reason):
      event.phase = .finalizing
      event.reason = reason == .sourceClosed ? .sourceClosed : .userStop
    case .resourceStopped(let resource):
      event = .init(.capture, .completed, operation: operation)
      event.resource = diagnosticResource(resource)
    case .resourceTimedOut(let resource):
      event = .init(.capture, .failed, operation: operation)
      event.fault = .finalization
      event.resource = diagnosticResource(resource)
    case .failed(let failure):
      event = .init(.capture, .failed, operation: operation).failing(failure)
      event.fault = fault(failure)
    case .finished:
      event = .init(.capture, .completed, operation: operation)
      event.phase = .finished
    }
    sink.record(event)
  }

  private static func diagnosticResource(_ resource: AudioCaptureLifecycleEvent.Resource)
    -> DiagnosticEvent.Resource
  {
    switch resource {
    case .microphone: .microphone
    case .application: .applicationAudio
    case .speech: .recognition
    }
  }

  private static func fault(_ failure: SessionFailure) -> DiagnosticEvent.Fault {
    switch failure.category {
    case .permissionDenied: .permissionDenied
    case .captureUnavailable: .captureUnavailable
    case .captureInterrupted: .captureInterrupted
    case .audioProcessing: .audioProcessing
    case .transcription: .transcription
    case .recordingSave: .recordingSave
    case .finalization: .finalization
    default: .unknown
    }
  }

  static func recordRecognition(_ update: AudioCaptureUpdate, operation: UUID, sink: DiagnosticSink)
  {
    switch update {
    case .transcriptionStopped(let failure):
      var event = DiagnosticEvent(.recognition, .failed, operation: operation).failing(failure)
      event.fault = .transcription
      sink.record(event)
    case .transcriptionRecovery(let recovery):
      let action: DiagnosticEvent.Action
      switch recovery.phase {
      case .retrying, .catchingUp: action = .recoveryStarted
      case .caughtUp: action = .completed
      case .stopped: action = .cancelled
      }
      var event = DiagnosticEvent(.recognition, action, operation: recovery.channel)
      event.relatedOperation = operation
      event.reason = .recognitionRecovery
      event.milliseconds = recovery.queuedSeconds * 1_000
      sink.record(event)
    default: break
    }
  }
  static func record(_ backlog: AudioCaptureBacklog, operation: UUID, sink: DiagnosticSink) {
    var failure = DiagnosticEvent(.capture, .failed, operation: operation)
    failure.fault = .audioProcessing
    switch backlog.pressure.limit {
    case .bytes: failure.reason = .captureByteLimit
    case .callbacks: failure.reason = .captureCallbackLimit
    case .duration: failure.reason = .captureDurationLimit
    }
    sink.record(failure)
    for (metric, count) in [
      (DiagnosticEvent.Metric.captureQueuedPackets, backlog.pressure.packets),
      (.captureQueuedBytes, backlog.pressure.bytes),
    ] {
      var event = DiagnosticEvent(.capture, .milestone, operation: operation)
      event.metric = metric
      event.count = count
      sink.record(event)
    }
    for (metric, seconds) in [
      (DiagnosticEvent.Metric.captureQueuedAudio, backlog.pressure.sourceDuration),
      (.captureMaximumQueueWait, backlog.timing.maximumQueueWait),
      (.captureMaximumProcessing, backlog.timing.maximumProcessing),
    ] {
      var event = DiagnosticEvent(.capture, .milestone, operation: operation)
      event.metric = metric
      event.milliseconds = seconds * 1_000
      sink.record(event)
    }
  }
}
