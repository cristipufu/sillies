import Foundation
import Testing

@testable import SilliesTextModels

@Test func cumulativeSnapshotsOnlyDeliverNewUnicodeText() throws {
  var snapshot = TextStreamSnapshot()
  #expect(try snapshot.append("Ștefan") == "Ștefan")
  #expect(try snapshot.append("Ștefan") == "")
  #expect(try snapshot.append("Ștefan 👋🏽") == " 👋🏽")
  #expect(throws: TextModelError.self) { try snapshot.append("Someone else") }
  #expect(throws: TextModelError.self) { try snapshot.append("Ștefan") }
}

@Test func textSnapshotsRejectOversizedInputBeforeCopyingIt() {
  var snapshot = TextStreamSnapshot()
  #expect(throws: TextModelError.self) {
    try snapshot.append(String(repeating: "x", count: TextInferenceWire.maximumMessageBytes))
  }
}

@Test func textEventsRoundTripWithoutConflatingToolArgumentsWithText() throws {
  let events: [TextInferenceEvent] = [
    .delta("Hello 👋🏽"), .finished(.init(output: .init(text: "Hello 👋🏽"))),
  ]
  for event in events {
    let data = try JSONEncoder().encode(event)
    let decoded = try JSONDecoder().decode(TextInferenceEvent.self, from: data)
    #expect(try JSONEncoder().encode(decoded) == data)
  }
}
