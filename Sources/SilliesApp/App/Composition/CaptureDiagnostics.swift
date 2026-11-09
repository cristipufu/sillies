import Foundation
import SilliesAudio
import SilliesDiagnostics
import SilliesSpeech

enum CaptureDiagnostics {
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
