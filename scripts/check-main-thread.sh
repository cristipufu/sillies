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

# 4. Window-list APIs must remain in the separate helper process. A worker thread alone
# still shares AppKit's CG connection lock and can deadlock its animation commit for 500 ms.
if matches=$(rg -n 'CGWindowList(CopyWindowInfo|Create|CreateDescriptionFromArray)[[:space:]]*\(' Sources/ | grep -v 'Sources/SilliesWindowMetadata/WindowMetadataService.swift:'); then
  printf '%s\n' "$matches" >&2
  fail "Window-list API called outside the metadata helper process"
fi

# 5. AXUIElementCopyAttributeValue / AXUIElementCopyMultipleAttributeValues are confined strictly to AccessibilityWindowSource.
if matches=$(grep -rnE 'AXUIElementCopy(Multiple)?AttributeValue' Sources/ 2>/dev/null | grep -v 'Sources/SilliesApp/Platform/AccessibilityWindowSource.swift:'); then
  printf '%s\n' "$matches" >&2
  fail "AXUIElementCopyAttributeValue called outside AccessibilityWindowSource"
fi

# 9. AccessibilityWindowSource must treat move/resize notifications as non-structural (no AX hierarchy IPC during window drags).
if ! grep -q 'isNonStructuralWindowNotification' Sources/SilliesApp/Platform/AccessibilityWindowSource.swift; then
  fail "AccessibilityWindowSource must skip AX hierarchy inspection on non-structural move/resize notifications"
fi

# 6. Every isolated worker must assert off-main-queue execution at runtime.
for worker in \
  Sources/SilliesApp/Platform/WindowServerSource.swift \
  Sources/SilliesApp/Platform/WindowTargetResolver.swift \
  Sources/SilliesApp/Platform/AccessibilityWindowSource.swift \
  Sources/SilliesApp/Platform/ApplicationIconCache.swift \
  Sources/SilliesApp/Platform/WindowMetadataReader.swift \
  Sources/SilliesApp/Platform/WindowMetadataClient.swift \
  Sources/SilliesApp/Platform/WindowMetadataConnection.swift \
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

# 8. Never pass NSImage to pasteboard.writeObjects on the main thread (encodes TIFF synchronously).
if matches=$(grep -rn 'writeObjects(' Sources/ 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "pasteboard.writeObjects called in Sources/; write pre-encoded PNG data off the main thread"
fi

# 10. Companion and skill overlay panels must never call setFrame(..., display: true).
if matches=$(grep -rn 'setFrame(.*display:[[:space:]]*true' Sources/SilliesApp/App/CompanionInstance.swift Sources/SilliesApp/Rendering/ Sources/SilliesApp/UI/SkillOverlayWindow.swift 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "Overlay panel called setFrame(..., display: true); use display: false to coalesce with CoreAnimation"
fi

# 11. CharacterRig must not read workspaceMotion.presentation() during live manipulation.
if matches=$(grep -rn 'workspaceMotion\.presentation()' Sources/SilliesApp/Rendering/ 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "workspaceMotion.presentation() called in Rendering/; track transform state directly to avoid render-tree readback stalls"
fi

# 12. SkillOverlayWindow must never use CAShapeLayer for window-sized drop outlines.
if matches=$(grep -rn 'CAShapeLayer' Sources/SilliesApp/UI/SkillOverlayWindow.swift 2>/dev/null); then
  printf '%s\n' "$matches" >&2
  fail "CAShapeLayer used in SkillOverlayWindow.swift; use hardware-composited CALayer borderWidth/cornerRadius to avoid full-window bitmap rasterization"
fi

# 13. SmoothnessBudgetTests must enforce frame budgets for all 4 interactive paths.
for path in '.windowMove' '.windowResize' '.windowSwitch' '.companionDrag'; do
  if ! grep -q "isWithinBudget(for: $path)" Tests/SilliesAppTests/SmoothnessBudgetTests.swift; then
    fail "SmoothnessBudgetTests.swift is missing budget assertion for $path"
  fi
done

# 14. AccessibilityWindowSource must inspect kAXMinimizedAttribute so minimized windows are excluded immediately.
if ! grep -q 'kAXMinimizedAttribute' Sources/SilliesApp/Platform/AccessibilityWindowSource.swift; then
  fail "AccessibilityWindowSource must inspect kAXMinimizedAttribute to exclude minimizing windows immediately"
fi

# 15. WindowTracking must treat miniaturize/deminiaturize as lifecycle discovery events.
if ! grep -q 'kAXWindowMiniaturizedNotification' Sources/SilliesApp/Platform/WindowTracking.swift; then
  fail "WindowTracking must handle kAXWindowMiniaturizedNotification for immediate minimize discovery"
fi

