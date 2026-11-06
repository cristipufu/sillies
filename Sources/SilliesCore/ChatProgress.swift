import Foundation

public enum ChatProgress: Sendable {
  case waitingForInference, preparingContext, generating
  case compacting
  case memory(ConversationMemory)
  case usingTool(String)
  case sources([ChatSource])
  case remembered(MemoryReceipt)
}
