import AppKit
import Testing

@testable import SilliesApp

@Test @MainActor func fileDialogHasOneParentAndIgnoresLateCompletionAfterCancellation() {
  let parent = NSWindow()
  parent.isReleasedWhenClosed = false
  var callbacks: [(NSApplication.ModalResponse) -> Void] = []
  let dialog = NativeFileDialog { _, owner, callback in
    #expect(owner === parent)
    callbacks.append(callback)
  }
  var completions = 0
  dialog.choose(NSSavePanel(), for: parent) { _ in completions += 1 }
  dialog.choose(NSSavePanel(), for: parent) { destination in
    #expect(destination == nil)
    completions += 1
  }
  #expect(callbacks.count == 1 && dialog.isPresented && completions == 1)
  dialog.cancel()
  #expect(!dialog.isPresented && completions == 2)
  dialog.choose(NSSavePanel(), for: parent) { _ in completions += 1 }
  callbacks[0](.OK)
  #expect(dialog.isPresented && completions == 2)
  callbacks[1](.cancel)
  #expect(!dialog.isPresented && completions == 3)
  dialog.cancel()
  #expect(completions == 3)
}

@Test @MainActor func closingFileDialogParentCancelsItsSelection() {
  let parent = NSWindow()
  parent.isReleasedWhenClosed = false
  let dialog = NativeFileDialog { _, _, _ in }
  var cancelled = false
  dialog.choose(NSSavePanel(), for: parent) { destination in cancelled = destination == nil }
  parent.close()
  #expect(cancelled && !dialog.isPresented)
}
