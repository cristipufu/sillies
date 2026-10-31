import Foundation

package struct MLXTextModelProvider: TextModelProvider {
  package let id = "mlx"
  private let executable: URL
  package init(
    executable: URL = Bundle.main.bundleURL.appendingPathComponent(
      "Contents/Helpers/SilliesTextInference.app/Contents/MacOS/SilliesTextInference")
  ) {
    self.executable = executable
  }
  package func prepare(_ configuration: TextModelPreparation) async throws -> any PreparedTextModel
  {
    try Task.checkCancellation()
    return TextWorkerModel(configuration: configuration, executable: executable)
  }
}
