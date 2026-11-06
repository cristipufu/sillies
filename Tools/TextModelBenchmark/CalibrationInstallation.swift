import Foundation
import SilliesModelStore
import SilliesTextModels

enum CalibrationInstallation {
  static func apply(receipt url: URL, models: URL) async throws {
    let receipt = try TextCalibrationStore.readReceipt(at: url)
    guard
      let manifest = try TextModelCatalog.bundled().manifests.first(where: {
        $0.modelID == receipt.identity.modelID
      }), try await ModelStore(root: models).isInstalled(manifest)
    else {
      throw ModelStoreError.notInstalled
    }
    guard let path = ProcessInfo.processInfo.environment["SILLIES_TEXT_HELPER"] else {
      throw TextModelError.unavailable(
        "Set SILLIES_TEXT_HELPER to the exact app helper used for the comparison.")
    }
    let store = TextCalibrationStore(
      directory: models.appendingPathComponent("Calibration"),
      helper: URL(fileURLWithPath: path))
    try await store.install(receipt, for: manifest)
    print(
      "Applied a reviewed prefill setting for \(manifest.modelID) on this Mac. Delete its Calibration receipt to restore defaults."
    )
  }
}
