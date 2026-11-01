import Foundation

/// A chat may retain an idle voice, but never prevents memory-pressure or budget eviction.
package actor SpeechModelLifetime {
  package nonisolated let id = UUID()
  package private(set) var isActive = true
  package init() {}
  package func end() { isActive = false }
}
