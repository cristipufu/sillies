import Foundation
import SilliesCore
import SilliesPersistence
import SilliesVault
import Testing

@Test func vaultListingKeepsItsCursorWhenLiveChangesMoveTheLoadedRange() {
  let newest = listingHeader(40)
  let first = listingHeader(30)
  let boundary = listingHeader(20)
  let remaining = listingHeader(10)
  var listing = VaultListing(
    .init(records: [first, boundary], total: 3, nextCursor: .init(boundary)))
  listing.refresh(
    .init(records: [newest, remaining], total: 4), changedIDs: [newest.id, remaining.id])
  #expect(listing.records.map(\.id) == [newest.id, first.id, boundary.id])
  listing.remove(boundary.id)
  #expect(listing.nextCursor?.id == boundary.id)
  listing.append(.init(records: [remaining], total: 3, nextCursor: nil))
  #expect(listing.records.map(\.id) == [newest.id, first.id, remaining.id])
  #expect(!listing.hasMore)
  listing.refresh(.init(records: [], total: 2), changedIDs: [first.id])
  #expect(listing.records.map(\.id) == [newest.id, remaining.id])
}

private func listingHeader(_ time: Double) -> SessionRecordHeader {
  .init(
    .init(
      kind: .record,
      origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Test")),
      metadata: .init(createdAt: Date(timeIntervalSince1970: time))))
}
