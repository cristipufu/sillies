#!/bin/bash
# Enforces main-thread responsiveness and crash-free invariants across Sources/.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() {
  printf 'MAIN-THREAD LINT FAILED: %s\n' "$1" >&2
  exit 1
}

# 1. No force-try, force-cast, or explicit runtime traps in production sources.
if matches=$(grep -rnE 'try!|as!|fatalError\(|preconditionFailure\(' Sources/ 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "Unsafe trap or force-unwrap in Sources/"
fi

# 2. No blocking process/thread/semaphore/condition/queue waits in production sources.
if matches=$(grep -rnE 'waitUntilExit\(|Thread\.sleep|usleep\(|DispatchSemaphore|NSCondition|NSConditionLock|DispatchGroup|\.wait\(|\.sync[[:space:]]*\{' Sources/ 2>/dev/null | grep -v 'WindowSnapshotService.swift'); then
  printf '%s\n' "$matches" >&2
  fail "Blocking thread/semaphore/condition/queue wait in Sources/"
fi

# Ensure WindowSnapshotService only runs waitUntilExit inside Task.detached.
if grep -n 'waitUntilExit' Sources/SilliesApp/Skills/WindowSnapshotService.swift >/dev/null 2>&1; then
  if ! grep -n 'Task\.detached' Sources/SilliesApp/Skills/WindowSnapshotService.swift >/dev/null 2>&1; then
    fail "WindowSnapshotService.waitUntilExit must run inside Task.detached"
  fi
fi

# 3. No synchronous file/image loading in UI or Rendering layers.
if matches=$(grep -rnE 'NSImage\(contentsOf:|Data\(contentsOf:|String\(contentsOf:' Sources/SilliesApp/UI/ Sources/SilliesApp/Rendering/ 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "Synchronous disk read in UI or Rendering layer"
fi

# 4. CGWindowListCopyWindowInfo is confined strictly to the isolated WindowServer workers.
if matches=$(grep -rn 'CGWindowListCopyWindowInfo' Sources/ 2>/dev/null | grep -vE 'Sources/SilliesApp/Platform/(WindowServerSource|WindowTargetResolver)\.swift:'); then
  printf '%s\n' "$matches" >&2
  fail "CGWindowListCopyWindowInfo called outside isolated platform workers"
fi

# 5. AXUIElementCopyAttributeValue is confined strictly to AccessibilityWindowSource.
if matches=$(grep -rn 'AXUIElementCopyAttributeValue' Sources/ 2>/dev/null | grep -v 'Sources/SilliesApp/Platform/AccessibilityWindowSource.swift:'); then
  printf '%s\n' "$matches" >&2
  fail "AXUIElementCopyAttributeValue called outside AccessibilityWindowSource"
fi

# 6. Every isolated worker must assert off-main-queue execution at runtime.
for worker in \
  Sources/SilliesApp/Platform/WindowServerSource.swift \
  Sources/SilliesApp/Platform/WindowTargetResolver.swift \
  Sources/SilliesApp/Platform/AccessibilityWindowSource.swift \
  Sources/SilliesApp/Platform/ApplicationIconCache.swift \
  Sources/SilliesApp/Skills/SessionVaultStore.swift
do
  if ! grep -q 'dispatchPrecondition(condition: \.notOnQueue(\.main))' "$worker"; then
    fail "Missing dispatchPrecondition(condition: .notOnQueue(.main)) in $worker"
  fi
done

# 7. SessionSummarizer.summarize must not be called in SilliesApp; always use summarizeOnWorker.
if matches=$(grep -rn 'SessionSummarizer\.summarize(' Sources/SilliesApp/ 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "Synchronous SessionSummarizer.summarize called in Sources/SilliesApp/; use summarizeOnWorker"
fi
