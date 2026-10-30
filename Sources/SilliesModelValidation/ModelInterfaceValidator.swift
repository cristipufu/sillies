import CoreML
import Foundation

/// Model schemas must remain compatible before an SDK can bind tensors or tokenizer outputs.
package enum ModelInterfaceValidator {
  private struct Feature: Equatable {
    let type: Int
    let optional: Bool
    let shape: [Int]?
    let dataType: Int?
    init(_ description: MLFeatureDescription) {
      type = description.type.rawValue
      optional = description.isOptional
      shape = description.multiArrayConstraint?.shape.map(\.intValue)
      dataType = description.multiArrayConstraint?.dataType.rawValue
    }
  }
  private struct Interface: Equatable {
    let inputs: [String: Feature]
    let outputs: [String: Feature]
    let states: [String: Feature]
  }
  package enum Failure: LocalizedError {
    case changedSchema(String)
    package var errorDescription: String? {
      switch self {
      case .changedSchema(let bundle):
        "The updated \(bundle) has a different runtime interface. The installed model remains selected."
      }
    }
  }

  @concurrent package static func validate(
    installed: URL, candidate: URL, bundles: [String]
  ) async throws {
    dispatchPrecondition(condition: .notOnQueue(.main))
    for bundle in bundles {
      try Task.checkCancellation()
      let previous = try interface(at: installed.appendingPathComponent(bundle))
      let updated = try interface(at: candidate.appendingPathComponent(bundle))
      guard previous == updated else { throw Failure.changedSchema(bundle) }
    }
  }

  private static func interface(at url: URL) throws -> Interface {
    try autoreleasepool {
      let configuration = MLModelConfiguration()
      configuration.computeUnits = .cpuOnly
      let model = try MLModel(contentsOf: url, configuration: configuration)
      let description = model.modelDescription
      return Interface(
        inputs: description.inputDescriptionsByName.mapValues(Feature.init),
        outputs: description.outputDescriptionsByName.mapValues(Feature.init),
        states: description.stateDescriptionsByName.mapValues(Feature.init))
    }
  }
}
