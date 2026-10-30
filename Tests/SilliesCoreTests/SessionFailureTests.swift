import Foundation
import SilliesCore
import Testing

@Test func ordinarySessionContentNeverRequestsPermissionRecovery() {
  for kind in CompanionSkillKind.allCases {
    let record = SessionRecord(
      kind: kind,
      origin: .init(characterID: "mochi", characterName: "Mochi", source: .init(appName: "Notes")),
      content: .init(
        notes: .init(
          summary:
            "Discuss system settings, screen recording permission, and permission needed tomorrow.")
      ))
    #expect(!record.requiresPermissionAccess)
    #expect(record.failure == nil)
  }
}

@Test func failureRecoveryIsIndependentOfMessageWording() throws {
  let failure = SessionFailure(
    category: .permissionDenied, message: "Accès refusé.", recovery: .openMicrophoneSettings)
  let record = SessionRecord(
    kind: .record,
    origin: .init(
      characterID: "mochi", characterName: "Mochi", source: .init(appName: "Microphone")),
    content: .init(
      notes: .init(summary: "Keep the useful notes"), processing: .init(failure: failure)))
  #expect(record.requiresPermissionAccess)
  #expect(record.failureMessage == "Accès refusé.")
  #expect(
    try JSONDecoder().decode(SessionRecord.self, from: JSONEncoder().encode(record)) == record)
  let unrelated = SessionFailure(category: .audioProcessing, message: "Check system settings.")
  #expect(unrelated.recovery == nil)
}

@Test(arguments: [
  (
    #"{"category":"futureDeviceError","message":"Keep this diagnostic","recovery":"openMicrophoneSettings"}"#,
    SessionFailure.Category.unknown
  ),
  (
    #"{"category":"permissionDenied","message":"Keep this diagnostic","recovery":"openFutureSettings"}"#,
    .permissionDenied
  ),
  (
    #"{"category":"futureDeviceError","message":"Keep this diagnostic","recovery":"openFutureSettings"}"#,
    .unknown
  ),
])
func futureFailureIdentifiersSurviveWithoutOfferingAnUnsupportedAction(
  _ json: String, _ category: SessionFailure.Category
) throws {
  let original = Data(json.utf8)
  let failure = try JSONDecoder().decode(SessionFailure.self, from: original)
  #expect(failure.category == category)
  #expect(failure.message == "Keep this diagnostic")
  #expect(failure.recovery == nil)
  let encoded = try JSONEncoder().encode(failure)
  let old = try #require(JSONSerialization.jsonObject(with: original) as? NSDictionary)
  let new = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
  #expect(old == new)
}

@Test(arguments: [
  #"{"category":123,"message":"Wrong category type"}"#,
  #"{"category":"future","recovery":"future"}"#,
  #"{"category":"future","message":"Wrong recovery type","recovery":[]}"#,
])
func malformedFailuresStillRejectInvalidData(_ json: String) {
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(SessionFailure.self, from: Data(json.utf8))
  }
}
