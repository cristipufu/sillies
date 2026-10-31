import XCTest

@testable import SilliesModelStore

final class TextModelCatalogTests: XCTestCase {
  func testModelsUsePinnedArtifacts() throws {
    let catalog = try TextModelCatalog.bundled()
    XCTAssertEqual(catalog.manifests.count, 6)
    for manifest in catalog.manifests { try manifest.validate() }
  }
}
