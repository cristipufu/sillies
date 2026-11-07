import Foundation
import Observation
import SilliesCore

@MainActor @Observable final class VaultDocumentModel {
  private let vault: SessionVaultStore
  let editor: VaultTextEditorModel
  let metadata: VaultMetadataEditor
  let playback = RecordingPlaybackModel()
  let recording: VaultRecordingNavigation
  let externalFiles: VaultFileReferencesModel
  private(set) var header: VaultDocumentHeader?
  private(set) var sections: [VaultDocumentSection] = []
  private(set) var isLoading = false
  private(set) var error: String?
  private(set) var speakerRecord: SessionRecord?
  var section = VaultDocumentSection.notes
  var showsFiles = false
  var title: String {
    get { metadata.title }
    set { metadata.title = newValue }
  }
  var tags: String {
    get { metadata.tags }
    set { metadata.tags = newValue }
  }
  var canNavigate: Bool { editor.canNavigate && metadata.canNavigate }
  private var generation = UUID()
  private var sectionRequest = UUID()
  private var speakerRequest = UUID()

  init(vault: SessionVaultStore) {
    self.vault = vault
    editor = VaultTextEditorModel(vault: vault)
    metadata = VaultMetadataEditor(vault: vault)
    recording = VaultRecordingNavigation(library: vault.library, editor: editor)
    externalFiles = VaultFileReferencesModel(library: vault.library)
    editor.onInteraction = { [weak recording] in recording?.pauseFollowing() }
  }

  func open(_ id: UUID, match: VaultBlockLocation? = nil) async {
    let token = UUID()
    generation = token
    isLoading = true
    playback.stop()
    recording.stop()
    externalFiles.stop()
    defer { if generation == token { isLoading = false } }
    await flush()
    guard generation == token, !Task.isCancelled, canNavigate else { return }
    do {
      await vault.waitUntilLoaded()
      try await vault.library.prepareDocument(id: id)
      let header = try await vault.library.documentHeader(id: id)
      let kinds = try await vault.library.sectionKinds(recordID: id)
      guard token == generation, !Task.isCancelled else { return }
      let recovered = try await vault.library.metadataDraft(id: id)
      guard token == generation, !Task.isCancelled else { return }
      metadata.load(header, recovered: recovered)
      self.header = header
      speakerRecord = nil
      sections = [.notes] + kinds.filter { ![.notes, .title, .labels].contains($0) }
      let preferred =
        kinds.contains(.notes) || header?.metadata.kind != .capture
        ? .notes
        : [.summary, .explanation, .transcript, .screenshotText, .stash].first(
          where: kinds.contains) ?? .notes
      section = match.map { sections.contains($0.section) ? $0.section : preferred } ?? preferred
      showsFiles = false
      error = nil
      let ordinal = match.flatMap { $0.section == section ? $0.ordinal : nil } ?? 0
      await editor.load(.init(recordID: id, section: section, ordinal: ordinal))
      guard token == generation, !Task.isCancelled, let header else { return }
      vault.prepareImage(for: header.source)
      if let link = header.metadata.link { vault.prepareImage(for: link) }
      if let audio = vault.audioURL(for: header.source) {
        await playback.prepare(audio)
        guard token == generation, !Task.isCancelled else { return }
        await recording.open(id)
      }
    } catch is CancellationError { return } catch {
      guard token == generation, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }

  @discardableResult func selectSection(_ section: VaultDocumentSection) async -> Bool {
    recording.pauseFollowing()
    guard let header, !isLoading else { return false }
    let token = generation
    let request = UUID()
    sectionRequest = request
    await editor.flush()
    guard editor.canNavigate, generation == token, self.header?.id == header.id,
      sectionRequest == request, !Task.isCancelled
    else { return false }
    await editor.load(.init(recordID: header.id, section: section))
    guard generation == token, sectionRequest == request, !Task.isCancelled,
      editor.location?.recordID == header.id, editor.location?.section == section
    else {
      return false
    }
    self.section = section
    showsFiles = false
    return true
  }

  func followAudio(recordID: UUID) async {
    guard header?.id == recordID, sections.contains(.transcript), !isLoading else { return }
    let token = generation
    guard await selectSection(.transcript), generation == token, header?.id == recordID,
      !Task.isCancelled
    else { return }
    recording.resumeFollowing()
  }

  func edit(_ edit: VaultDocumentEdit, recordID: UUID) async {
    guard header?.id == recordID, !isLoading else { return }
    let token = generation
    do {
      let updated = try await vault.editWorkspace(id: recordID, edit)
      guard generation == token, header?.id == recordID, !Task.isCancelled else { return }
      header = updated
      error = nil
    } catch is CancellationError { return } catch {
      guard generation == token, header?.id == recordID, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }

  func moveToTrash(recordID: UUID) async {
    guard header?.id == recordID, !isLoading else { return }
    let token = generation
    await flush()
    guard generation == token, header?.id == recordID, canNavigate, !Task.isCancelled else {
      return
    }
    await edit(.moveToTrash, recordID: recordID)
  }

  func saveTitle() async {
    await metadata.flush()
  }
  func refreshHeader() async {
    guard let id = header?.id else { return }
    let token = generation
    do {
      let updated = try await vault.library.documentHeader(id: id)
      guard generation == token, header?.id == id, !Task.isCancelled else { return }
      if updated == nil, !canNavigate {
        error = String(
          localized: "This item was removed. Copy your changes or save them as a new note.")
        return
      }
      if let updated { metadata.refresh(updated) }
      header = updated
      if updated == nil { playback.stop() }
      if let link = updated?.metadata.link { vault.prepareImage(for: link) }
    } catch is CancellationError { return } catch {
      guard generation == token, header?.id == id, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }
  func saveTags() async {
    await metadata.flush()
  }
  func showSpeakers() async {
    guard let id = header?.id else { return }
    let token = generation
    let request = UUID()
    speakerRequest = request
    do {
      let record = try await vault.record(id: id)
      guard token == generation, speakerRequest == request, header?.id == id, !Task.isCancelled
      else { return }
      speakerRecord = record
    } catch is CancellationError { return } catch {
      guard token == generation, speakerRequest == request, !Task.isCancelled else { return }
      self.error = error.localizedDescription
    }
  }
  func hideSpeakers() {
    speakerRequest = UUID()
    speakerRecord = nil
  }
  func flush() async {
    await editor.flush()
    await metadata.flush()
  }
  func stop() {
    generation = UUID()
    isLoading = false
    editor.stop()
    metadata.stop()
    playback.stop()
    recording.stop()
    externalFiles.stop()
    hideSpeakers()
  }
}
