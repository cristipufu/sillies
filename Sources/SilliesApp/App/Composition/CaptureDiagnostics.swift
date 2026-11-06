import Foundation
import SilliesAudio
import SilliesDiagnostics

enum CaptureDiagnostics {
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
