# Teams: a bound mascot disappeared during Listen/Participate

The visibility check treated `CGWindowListOption.optionAll` as a front-to-back window stack.
That option is an inventory of on-screen and hidden windows. In the captured live state it put
background application windows ahead of the active Teams meeting, causing false full-coverage
calculations. The bound mascot and its controls were then deliberately hidden by Sillies.

Apple documents front-to-back ordering for
[`optionOnScreenOnly`](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optiononscreenonly),
but does not provide that guarantee for
[`optionAll`](https://developer.apple.com/documentation/coregraphics/cgwindowlistoption/optionall).
The live comparison reproduced that distinction. A wider Teams frame no longer appeared fully
covered by the incorrectly ordered background rectangles, explaining why the mascot could return
when the meeting layout changed. The process had not crashed.

## Fix

`BoundWindowSnapshots` now reads the ordered on-screen stack. It consults the unordered inventory
only when a requested window is missing from that stack, preserving the distinction between a
hidden window, a closed window and an unavailable metadata read. The ordinary visible-window path
uses one shared snapshot; hidden-window lookup can add one fallback snapshot for the whole batch.
Reads stay on the existing metadata worker, without new timers, AX enumeration or pixel polling.

System surfaces at Dock level and above can report screen-sized bounds and alpha 1 while containing
transparent regions. Their rectangles are excluded from application-occlusion calculations. Normal,
floating and modal application windows still cover targets, and registered transparent Sillies
overlays remain excluded.

The recording control bar had a separate stacking defect: the bound mascot used the host's native
level (normal level 0 in the observed meeting), while its HUD used overlay level 2. Ordering the HUD
relative to the mascot could not overcome that difference, so foreground apps covered the mascot
but left its controls visible. The HUD now holds a weak reference to its companion panel, inherits
that panel's actual level and orders immediately above it. The companion remains the single owner
of its stacking policy; the HUD follows normal, floating and pickup transitions without duplicating
that policy or retaining the companion.

## Validation

- A regression uses sanitized geometry from the live failure, with deliberately different inventory
  and on-screen orders. It verifies that the inventory is not consulted for a visible target.
- Further cases cover hidden and closed targets, failed primary/fallback reads, empty requests,
  transparent system surfaces, and genuine floating/modal occlusion.
- The final targeted headless run passed all ten selected test functions. The existing ordered-out
  Teams WebView and explicit on-screen-flag regressions still pass.
- A headless regression checks HUD level transitions, stable window identity, unchanged
  recording state and nonactivating behavior. The layout-cache regression also runs headlessly now,
  checking 120 updates without showing a window or repeatedly measuring its content.
- The full `make check` validation is recorded with the
  [memory-tool investigation](memory-tool-contracts-2026-11-03.md#engineering-validation).

The user's recording app was left running throughout validation. After the user requested a restart,
Sillies quit gracefully and the verified build was installed at the existing local app path. The new
process started successfully; a live Teams walkthrough with that build remains pending. No meeting
titles, screenshots, participant details or recording contents are included in this report or its
fixtures.
