package protocol TextInserting: Sendable {
  func capture(_ application: FrontmostApplication) async throws -> TextDestination
  func insert(_ text: String, into destination: TextDestination) async throws
  func release(_ destination: TextDestination) async
}
