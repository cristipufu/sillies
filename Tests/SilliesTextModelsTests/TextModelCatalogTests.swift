import XCTest

@testable import SilliesModelStore

final class TextModelCatalogTests: XCTestCase {
  func testFourModelsUsePinnedArtifacts() throws {
    let catalog = try TextModelCatalog.bundled()
    XCTAssertEqual(catalog.manifests.count, 4)
    for manifest in catalog.manifests { try manifest.validate() }
  }
}
