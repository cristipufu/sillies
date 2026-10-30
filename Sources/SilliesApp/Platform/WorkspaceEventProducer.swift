import SilliesCore

@MainActor
protocol WorkspaceEventProducer: AnyObject {
  var onEvent: ((WorkspaceEvent) -> Void)? { get set }
  func start()
  func stop()
  func configure(enabled: Bool, tracksWindows: Bool)
}
