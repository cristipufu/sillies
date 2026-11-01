import Foundation
import SilliesCore
import Testing

@testable import SilliesChat

@Test func conversationWriteAcknowledgementPreservesEditsArrivingDuringSave() {
  var buffer = ConversationWriteBuffer()
  let message = ChatMessage(role: .companion, text: "First")
  buffer.stage(message)
  let firstRevision = buffer.revision
  buffer.stage(message.withText("First and second"))
  buffer.changedCheckpoint()
  buffer.acknowledge(firstRevision)
  let handle = ConversationHandle(companionID: "pogo", generation: UUID())
  let update = buffer.update(handle: handle, checkpoint: .init(draft: "Unsent"), at: Date())
  #expect(buffer.needsSave)
  #expect(update.messages.count == 1)
  #expect(update.messages.first?.text == "First and second")
  #expect(update.checkpoint.draft == "Unsent")
  buffer.acknowledge(buffer.revision)
  #expect(!buffer.needsSave)
}

@Test func conversationRemovedMessageCannotReturnFromAnEarlierAcknowledgement() {
  var buffer = ConversationWriteBuffer()
  let message = ChatMessage(role: .companion, text: "Interrupted")
  buffer.stage(message)
  let savingRevision = buffer.revision
  buffer.remove(message.id)
  buffer.acknowledge(savingRevision)
  let update = buffer.update(
    handle: .init(companionID: "pogo", generation: UUID()), checkpoint: .init(), at: Date())
  #expect(update.messages.isEmpty)
  #expect(update.removedMessageIDs == [message.id])
  #expect(buffer.needsSave)
}
