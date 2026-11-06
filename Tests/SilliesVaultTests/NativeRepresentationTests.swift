import Foundation
import SilliesTextModels
import Testing

@testable import SilliesReasoning
@testable import SilliesVault

/// Opt-in observations, not automatic quality passes. Review replies, calls and persisted state.
@Test(.enabled(if: ProcessInfo.processInfo.environment["SILLIES_NATIVE_REPRESENTATION"] != nil))
func nativeRepresentationControlsPreserveAppToolsAndPersistence() async throws {
  let environment = ProcessInfo.processInfo.environment
  let variant = try #require(
    environment["SILLIES_NATIVE_REPRESENTATION"].flatMap(
      NativeRepresentationVariant.init(rawValue:)))
  let selected = environment["SILLIES_NATIVE_CASES"]?.split(separator: ",").map(String.init)
  let cases = NativeRepresentationCase.controls.filter { selected?.contains($0.id) ?? true }
  try #require(!cases.isEmpty && (selected == nil || cases.count == selected?.count))
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
  let backend = variant.backend()
  try #require(await backend.availabilityNotice(localeIdentifier: "en") == nil)
  let probe = NativeRepresentationProbe(
    variant: variant, backend: backend,
    vault: VaultLibrary(directory: directory.appendingPathComponent("Vault")),
    conversations: ConversationLibrary(directory: directory.appendingPathComponent("Chat")))
  var observations: [NativeRepresentationObservation] = []
  do {
    try await probe.prepare()
    for item in cases { observations.append(try await probe.observe(item)) }
  } catch {
    await backend.stop()
    throw error
  }
  await backend.stop()
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
  let data = try encoder.encode(observations)
  let output = try #require(environment["SILLIES_NATIVE_REPRESENTATION_OUTPUT"])
  try data.write(to: URL(fileURLWithPath: output), options: .atomic)
  print("NATIVE REPRESENTATION: \(variant.rawValue), \(observations.count) observations, \(output)")
}
