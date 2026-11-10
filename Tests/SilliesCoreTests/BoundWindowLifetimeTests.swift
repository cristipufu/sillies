import SilliesCore
import Testing

@Test func boundWindowLifetimeRequiresVerifiedIdentityBeforeAbsenceCanCloseIt() {
  var lifetime = BoundWindowLifetime()
  lifetime.observe(.absent)
  #expect(lifetime.state == .unverified)
  lifetime.observe(.present)
  lifetime.observe(.unavailable)
  #expect(lifetime.state == .open)
  lifetime.observe(.absent)
  #expect(lifetime.state == .closed)
  lifetime.observe(.present)
  #expect(lifetime.state == .closed)
}
