/// A missing window is evidence of closure only after its native identity was verified.
public struct BoundWindowLifetime: Sendable {
  public enum Observation: Sendable { case present, absent, unavailable }
  public enum State: Sendable { case unverified, open, closed }
  public private(set) var state: State = .unverified

  public init() {}

  public mutating func observe(_ observation: Observation) {
    guard state != .closed else { return }
    switch observation {
    case .present: state = .open
    case .absent: if state == .open { state = .closed }
    case .unavailable: break
    }
  }
}
