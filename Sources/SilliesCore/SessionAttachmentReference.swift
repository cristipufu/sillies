/// Media presentation needs filenames, not a loaded transcript.
public protocol SessionAttachmentReference: Sendable {
  var imageFilename: String? { get }
  var audioFilename: String? { get }
}
extension SessionRecord: SessionAttachmentReference {}
extension SessionRecordHeader: SessionAttachmentReference {}
