import SilliesReasoning

package struct WritingTextServices: Sendable {
  package typealias Transform = @Sendable (String, LocalTextOperation) async throws -> String
  package let insertion: any TextInserting
  package let cleanup: BoundedTextCleanup
  package let transform: Transform
  package init(
    insertion: any TextInserting, cleanup: BoundedTextCleanup, transform: @escaping Transform
  ) {
    self.insertion = insertion
    self.cleanup = cleanup
    self.transform = transform
  }
}
