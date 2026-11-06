/// Feature-facing capability. The composition root owns retention, export and lifecycle.
package struct DiagnosticSink: Sendable {
  private let receive: @Sendable (DiagnosticEvent) -> Void
  package static let disabled = DiagnosticSink { _ in }
  package init(_ receive: @escaping @Sendable (DiagnosticEvent) -> Void) { self.receive = receive }
  package func record(_ event: DiagnosticEvent) { receive(event) }
}
