import Foundation

public enum ChatProgress: Sendable {
  case compacting
  case memory(ConversationMemory)
  case usingTool(String)
  case sources([ChatSource])
  case remembered(MemoryReceipt)
}
