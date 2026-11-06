import Foundation

public struct MemoryIndexItem: Sendable {
  public let owner: String
  public let memory: CompanionMemory
  public init(owner: String, memory: CompanionMemory) {
    self.owner = owner
    self.memory = memory
  }
  public var text: String { memory.key + ": " + memory.value }
}
