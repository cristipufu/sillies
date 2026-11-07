import Foundation
import Observation
import SilliesCore
import SilliesVault

/// Uses the player's existing clock. Reading or editing always takes priority over following audio.
@MainActor @Observable final class VaultRecordingNavigation {
  private let library: VaultLibrary
  private let editor: VaultTextEditorModel
  private var recordID: UUID?
  private var generation = UUID()
  private var followed: VaultBlockLocation?
  private(set) var bookmarks: [VaultRecordingBookmark] = []
  private(set) var error: String?
  private(set) var isFollowing = false
  init(library: VaultLibrary, editor: VaultTextEditorModel) {
    self.library = library
    self.editor = editor
  }
  func open(_ id: UUID) async {
    stop()
    recordID = id
    await reloadBookmarks()
  }
  func pauseFollowing() { isFollowing = false }
  func resumeFollowing() {
    followed = nil
    isFollowing = true
  }
  func follow(seconds: Double) async {
    guard isFollowing, let recordID, editor.location?.section == .transcript else { return }
    let token = generation
    do {
      guard let location = try await library.transcriptLocation(id: recordID, seconds: seconds),
        token == generation, isFollowing, !Task.isCancelled, location != followed
      else { return }
      if !editor.blocks.contains(where: { $0.location == location }) { await editor.load(location) }
      guard token == generation, isFollowing, !Task.isCancelled else { return }
      editor.reveal(location)
      followed = location
    } catch is CancellationError { return } catch {
      guard token == generation else { return }
      self.error = error.localizedDescription
      pauseFollowing()
    }
  }
  func addBookmark(seconds: Double, recordID: UUID) async {
    guard self.recordID == recordID else { return }
    let selected = editor.selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
    let label = String(selected.unicodeScalars.prefix(VaultRecordingBookmark.maximumLabelScalars))
    await save(.init(recordID: recordID, seconds: seconds, label: label))
  }
  func save(_ bookmark: VaultRecordingBookmark) async {
    do {
      try await library.saveRecordingBookmark(bookmark)
      await reloadBookmarks()
    } catch { report(error, recordID: bookmark.recordID) }
  }
  func remove(_ bookmark: VaultRecordingBookmark) async {
    do {
      try await library.removeRecordingBookmark(bookmark)
      await reloadBookmarks()
    } catch { report(error, recordID: bookmark.recordID) }
  }
  private func reloadBookmarks() async {
    guard let recordID else { return }
    let token = generation
    do {
      let saved = try await library.recordingBookmarks(id: recordID)
      guard token == generation, !Task.isCancelled else { return }
      bookmarks = saved
      error = nil
    } catch { report(error, recordID: recordID) }
  }
  private func report(_ error: Error, recordID: UUID) {
    guard !(error is CancellationError) else { return }
    fputs("Vault recording navigation failed: \(error)\n", stderr)
    guard self.recordID == recordID else { return }
    self.error = error.localizedDescription
  }
  func stop() {
    generation = UUID()
    recordID = nil
    isFollowing = false
    followed = nil
    bookmarks = []
    error = nil
  }
}
