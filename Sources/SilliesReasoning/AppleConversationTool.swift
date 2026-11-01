import Foundation
import FoundationModels
import SilliesCore

struct AppleConversationTool: Tool {
  typealias Arguments = GeneratedContent
  let name: String
  let description: String
  let parameters: GenerationSchema
  private let invoke: @Sendable (ConversationToolCall) async throws -> String

  init(_ definition: ConversationToolDefinition, toolbox: ConversationToolbox) throws {
    try self.init(definition, invoke: toolbox.invoke)
  }

  init(
    _ definition: ConversationToolDefinition,
    invoke: @escaping @Sendable (ConversationToolCall) async throws -> String
  ) throws {
    name = definition.name
    description = definition.description
    self.invoke = invoke
    parameters = try GenerationSchema(
      root: DynamicGenerationSchema(
        name: definition.name + "Arguments",
        properties: definition.parameters.map {
          DynamicGenerationSchema.Property(
            name: $0.name, description: $0.description, schema: Self.schema($0))
        }), dependencies: [])
  }
  private static func schema(_ parameter: ConversationToolDefinition.Parameter)
    -> DynamicGenerationSchema
  {
    switch parameter.kind {
    case .string: DynamicGenerationSchema(type: String.self)
    case .integer: DynamicGenerationSchema(type: Int.self)
    case .boolean: DynamicGenerationSchema(type: Bool.self)
    case .choice(let choices): DynamicGenerationSchema(name: parameter.name, anyOf: choices)
    }
  }
  func call(arguments: GeneratedContent) async throws -> String {
    try await invoke(
      .init(id: UUID().uuidString, name: name, arguments: Data(arguments.jsonString.utf8)))
  }
}
