import Foundation
import SilliesCore

/// Decode before accessing storage so invocation mistakes remain distinct from persistence failures.
package enum ConversationToolArguments {
  package struct Failure: Error {
    fileprivate let parameter: String?

    func response(for definition: ConversationToolDefinition, remainingCalls: Int) throws -> String
    {
      let knownParameter = parameter.flatMap { name in
        definition.parameters.contains(where: { $0.name == name }) ? name : nil
      }
      let result = Rejection(parameter: knownParameter, remainingCalls: remainingCalls)
      return String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
    }
  }

  package static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value
  {
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch let error as DecodingError {
      throw Failure(parameter: parameter(in: error))
    }
  }

  package static func require<Value>(_ value: Value?, parameter: String? = nil) throws -> Value {
    guard let value else { throw Failure(parameter: parameter) }
    return value
  }

  private static func parameter(in error: DecodingError) -> String? {
    switch error {
    case .keyNotFound(let key, let context):
      return context.codingPath.first?.stringValue ?? key.stringValue
    case .typeMismatch(_, let context), .valueNotFound(_, let context),
      .dataCorrupted(let context):
      return context.codingPath.first?.stringValue
    @unknown default: return nil
    }
  }

  private struct Rejection: Encodable {
    let status = "notExecuted"
    let reason = "invalidArguments"
    let parameter: String?
    let remainingCalls: Int
    let coverage = """
      No operation was performed because the arguments did not match this tool's declared inputs.
      Correct the indicated argument and include every required field before retrying.
      Copy record identifiers exactly from returned results; do not invent identifiers.
      """
  }
}
