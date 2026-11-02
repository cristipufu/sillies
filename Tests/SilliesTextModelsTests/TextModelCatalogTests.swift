import XCTest

@testable import SilliesModelStore

final class TextModelCatalogTests: XCTestCase {
  func testModelsUsePinnedArtifacts() throws {
    let catalog = try TextModelCatalog.bundled()
    XCTAssertFalse(catalog.manifests.isEmpty)
    for manifest in catalog.manifests {
      try manifest.validate()
      let release = try XCTUnwrap(manifest.model.release)
      XCTAssertNotNil(release.date.wholeMatch(of: /\d{4}-\d{2}-\d{2}/))
      XCTAssertEqual(release.sourceURL.scheme, "https")
      XCTAssertFalse(manifest.model.license.isEmpty)
    }
  }
}
