/// The capture owner supplies live updates and optional content-free overload diagnostics.
package struct AudioCaptureEvents: Sendable {
  let update: @Sendable (AudioCaptureUpdate) -> Void
  let reportOverload: @Sendable (AudioCaptureBacklog) -> Void

  package init(
    update: @escaping @Sendable (AudioCaptureUpdate) -> Void,
    reportOverload: @escaping @Sendable (AudioCaptureBacklog) -> Void = { _ in }
  ) {
    self.update = update
    self.reportOverload = reportOverload
  }
}
