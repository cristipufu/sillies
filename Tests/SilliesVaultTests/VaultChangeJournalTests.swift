import Foundation
import SilliesVault
import Testing

@Test func vaultInvalidationTracksChangedRecordsAndFallsBackAfterBoundedHistory() {
  var journal = VaultChangeJournal()
  let selected = UUID()
  let other = UUID()
  journal.record([selected])
  let selectedRevision = journal.revision(for: selected)
  journal.record([other])
  #expect(journal.revision(for: selected) == selectedRevision)
  if case .records(let ids) = journal.changes(since: selectedRevision) {
    #expect(ids == [other])
  } else {
    Issue.record("A retained revision must have an incremental change set")
  }
  for _ in 0..<300 { journal.record([UUID()]) }
  if case .reload = journal.changes(since: selectedRevision) {
  } else {
    Issue.record("An expired revision must reload instead of missing changes")
  }
  let beforeReset = journal.version
  journal.reset()
  if case .reload = journal.changes(since: beforeReset) {
  } else {
    Issue.record("Clearing the Vault must invalidate old listings")
  }
}
