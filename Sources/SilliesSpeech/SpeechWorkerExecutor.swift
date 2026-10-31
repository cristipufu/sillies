import Dispatch

/// A real worker queue also confines actor destruction. Default actor executors
/// can claim an uncontended actor on the thread releasing its last reference.
package final class SpeechWorkerExecutor: SerialExecutor {
  private let queue = DispatchQueue(label: "app.sillies.speech-model", qos: .utility)

  package init() {}

  package func enqueue(_ job: consuming ExecutorJob) {
    let job = UnownedJob(job)
    let qos: DispatchQoS =
      job.priority.rawValue >= TaskPriority.userInitiated.rawValue ? .userInitiated : .utility
    queue.async(qos: qos, flags: .enforceQoS) {
      job.runSynchronously(on: self.asUnownedSerialExecutor())
    }
  }

  package func checkIsolated() { dispatchPrecondition(condition: .onQueue(queue)) }
}
