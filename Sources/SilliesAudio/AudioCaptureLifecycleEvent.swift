import SilliesCore

/// Content-free transitions. Native identifiers and captured content never enter this contract.
package enum AudioCaptureLifecycleEvent: Sendable {
  package enum Resource: Sendable, CaseIterable, Hashable { case microphone, application, speech }
  case capturing
  case finishing(SessionEndReason)
  case resourceStopped(Resource)
  case resourceTimedOut(Resource)
  case failed(SessionFailure)
  case finished
}
