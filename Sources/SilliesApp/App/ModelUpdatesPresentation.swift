import Foundation
import Observation
import SilliesModelStore

@MainActor @Observable
final class ModelUpdatesPresentation {
  enum Activity { case active, suspended }
  private static let preferenceKey = "automaticallyCheckSpeechModelUpdates"
  private static let schedulingInterval: TimeInterval = 60 * 60
  private(set) var checksAutomatically: Bool
  private(set) var snapshot = ModelUpdateSnapshot()
  private(set) var isChecking = false
  private(set) var error: String?
  @ObservationIgnored private let checker: ModelUpdateChecker
  @ObservationIgnored private let registry: SpeechRuntimeRegistry
  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private var activity = Activity.suspended
  @ObservationIgnored private var scheduled: Task<Void, Never>?
  @ObservationIgnored private var manual: Task<Void, Never>?

  init(checker: ModelUpdateChecker, registry: SpeechRuntimeRegistry, defaults: UserDefaults) {
    self.checker = checker
    self.registry = registry
    self.defaults = defaults
    checksAutomatically =
      defaults.object(forKey: Self.preferenceKey) == nil
      || defaults.bool(forKey: Self.preferenceKey)
  }

  func enableAutomaticChecks() {
    checksAutomatically = true
    defaults.set(true, forKey: Self.preferenceKey)
    resumeSchedule()
  }

  func disableAutomaticChecks() {
    checksAutomatically = false
    defaults.set(false, forKey: Self.preferenceKey)
    scheduled?.cancel()
    scheduled = nil
  }

  func setActivity(_ activity: Activity) {
    self.activity = activity
    switch activity {
    case .active: resumeSchedule()
    case .suspended:
      scheduled?.cancel()
      scheduled = nil
    }
  }

  func load() async {
    do { snapshot = try await checker.load() } catch { report(error) }
  }

  func checkNow() {
    guard manual == nil, !isChecking else { return }
    manual = Task(priority: .utility) { [weak self] in
      await self?.check(.manual)
      self?.manual = nil
    }
  }

  func stop() {
    activity = .suspended
    scheduled?.cancel()
    scheduled = nil
    manual?.cancel()
    manual = nil
  }

  private func resumeSchedule() {
    guard checksAutomatically, activity == .active, scheduled == nil else { return }
    scheduled = Task(priority: .utility) { [weak self] in
      while !Task.isCancelled {
        await self?.check(.scheduled)
        do { try await Task.sleep(for: .seconds(Self.schedulingInterval)) } catch { return }
      }
    }
  }

  private func check(_ check: ModelUpdateChecker.Check) async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      let models = try await registry.modelCatalog().manifests
      let result = try await checker.check(check, models: models)
      try Task.checkCancellation()
      snapshot = result
      error = nil
    } catch is CancellationError {} catch { report(error) }
  }

  private func report(_ error: Error) {
    self.error = error.localizedDescription
    fputs("Model update check: \(error.localizedDescription)\n", stderr)
  }
}
