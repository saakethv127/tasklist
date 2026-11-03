# Validation

Tested on Apple Silicon, macOS 27.2, with Xcode 27.2 on November 2, 2026. Build with `./scripts/build.sh`; run the core suite with `./scripts/test.sh`.

## Automated checks

All eight Swift Testing tests pass:

- Nested tasks stay in their own tab; deleting a parent removes all descendants and preserves unrelated tasks.
- Deleting tabs maintains a valid selection and leaves an empty Inbox when deleting the last tab.
- Search includes tab names, nested tasks, parent context, Markdown source, and completed items.
- Atomic JSON persistence round-trips Unicode, notes, completion state, and selected tab.
- Corrupt data and newer formats are rejected without changing the original file.
- Parent cycles and orphaned tasks are rejected.
- Task files without appearance fields still load; individual tab colors and icons round-trip without changing other tabs or their tasks.
- Ten searches across a 1,000-task workspace completed in 25 ms total in the final core run (about 2.5 ms per search).

## Live app checks

An isolated `/tmp/tasklist-qa.json` file was used; test content is not included in the app or repository.

- Quick-add accepts typing and Return, saves, and persists through app restarts.
- Command-K focuses search immediately. Filtered rows display the matching task/subtask and its tab/parent context. Clicking a subtask result opens the correct detail view in its owning tab.
- Command-T focuses a new-tab dialog. Typing a name and pressing Return creates and selects an independent list. Immediate typing after Command-T was retested in the installed app after replacing deferred dialog focus with a native text field.
- Command-Left/Right changes tabs. Command-Option-Left/Right moves between the task list and details.
- Task details show subtasks, editable titles, and descriptions. The editor receives focus when opened.
- Markdown headings, bold text, bullets, and hyperlinks render. Clicking a Markdown hyperlink opened the requested GitHub repository in the browser.
- Command-W requests tab deletion. Escape cancels; Return confirms. The tab and its tasks are removed only after confirmation.
- Command-Delete requests task/subtask deletion. Both cancellation and confirmation were exercised. Parent deletion reports the subtask count and removes descendants.
- Undo restores deleted tabs and parent/child tasks. Completing a subtask updates the remaining count, and hiding completed items hides that row.
- The fixed 400 × 560-point panel appears at the display's lower-left with a 16-point inset from the usable screen bounds. The native glass surface and rounded edges were inspected in list, detail, search, and modal states.
- The panel was verified visible above fullscreen Chrome (`isOnActiveSpace` and visible occlusion state), and on the regular desktop after exiting fullscreen. On hide, Chrome remained the frontmost app, the panel became non-key and invisible, and Chrome's desktop was preserved.

The OS-global Command-Option-semicolon shortcut registers successfully without Accessibility permissions. The user confirmed with the physical keyboard that it opens and hides correctly from other apps and across desktop Spaces, without switching desktops. App-local shortcuts and panel show/hide behavior were also exercised through the UI.

## Performance

Measurements use the optimized, locally signed Xcode release build. Optional diagnostics are enabled only for measurement, via `--diagnostics /tmp/tasklist-diagnostics.json`.

| Measurement | Observed result |
| --- | --- |
| Initial panel show handler | 96 ms on the instrumented launch |
| Warm show/hide handlers, 42 operations including 20 repeated cycles | Median 14.4 ms; p95 29.5 ms; maximum 32.1 ms |
| Physical footprint at startup | 27.8 MB |
| Physical footprint after 20 cycles | 28.4 MB (29.0 MB peak) |
| Physical footprint after task editing, Markdown, and menus | 37.3 MB (38.4 MB peak) |
| Resident memory after the full interaction session | About 126 MB, including shared mappings |
| Hidden idle, 20 seconds | `ps` displayed 0.0% CPU at all three samples; cumulative CPU increased 0.04 seconds, about 0.2% of one core |

Memory was measured with `vmmap -summary` and `ps`. Physical footprint better represents this app's memory cost than RSS, which includes shared framework mappings. Show/hide timings cover app-side handling and synchronous display work, not physical key-to-photon latency; they should not be interpreted as a full display latency benchmark. Twenty cycles provide a short stability check, not a multi-hour leak test.

The app has no network activity, polling loop, or periodic refresh timer. It saves after a 250 ms typing debounce and flushes dirty data on hide/quit. Repeated toggling without edits does not rewrite the task file. Task rows and search results are rendered lazily, and hierarchy traversal groups children once rather than repeatedly scanning the whole list.

## Scope

The tab appearance update was built with Xcode and inspected in the running app. Preset color changes and bundled SVG icons render in the tab strip and survive restarting the app. The appearance popover provides 12 color presets, 12 icons, and a custom-color action backed by `NSColorPanel`. The native Apple color palette was opened in the installed app; choosing Blue persisted its custom sRGB value (`0433FF`). The tab was restored to Neutral afterward. The panel now explicitly uses dark appearance with neutral header controls and 95% window opacity.

Runtime verification was on the machine above. The macOS 14–15 material fallback, other keyboard layouts, external-monitor configurations, and Stage Manager were not available in this test session. The hotkey uses the ANSI semicolon key position, documented in the README. The bundle is locally signed for personal use, not notarized for distribution.

## Full Lucide collection

Bundled 2,019 Lucide SVG icons with local name, tag, and category search. All 10 core tests pass, including catalog packaging, stable persisted identifiers, keyword matching, and legacy appearance compatibility. 100 searches across the catalog took 0.343 seconds in the test build. The release app occupies 8.8 MB on disk. Native UI checks confirmed the full catalog count, `airplane` matching Plane, Return selection, selected icon rendering, and the empty-result state. The upstream license and pinned source manifest ship inside the app.

## Flat frosted backdrop and appearance access

Replaced refractive glass with an active behind-window HUD blur and a 30% black tint. The content sits outside the visual-effect view to avoid vibrancy. Window alpha is now 1 so unblurred background text cannot leak through compositor transparency. Release build succeeds. Native UI checks confirmed that naming a new tab opens its color/icon picker, Escape dismisses it, and Command-Shift-A reopens it for the current tab. Visually inspected the flat backdrop and rounded clipping.

## Compact rows and nested disclosure

Reduced task-row padding and detail section gaps, moved subtask counts inline, and centered the detail title beside its completion circle. Native UI checks with a three-level test tree verified independent nested collapse, full parent collapse, and preservation of child collapse state when the parent is reopened. Inspected screenshots of the compact main list and detail title/subtask layout. Release build succeeds.

## Task history and swipe navigation

All 12 core tests pass, including history round trips, forward-branch replacement, deleted-entry removal, swipe reversal, vertical direction locking, unavailable directions, and single commit per gesture. Release build succeeds. Native keyboard checks exercised list → task → subtask → back → forward → back → back to list through the same navigation methods used by swipes. The gesture handler only accepts precise phased scroll input, excludes momentum from navigation, and leaves the tab strip alone. A clipped circular edge indicator tracks progress and springs away after completion/cancellation. Physical two-finger feel and haptic feedback require hands-on trackpad validation; desktop automation does not reproduce that input reliably.

## Symmetric swipe progress

Replaced the separately clipped full-circle strokes with a visible half-circle stroke and a mirrored copy for forward navigation. Rendered the actual SwiftUI indicator at 25%, 50%, 75%, and 100% using ImageRenderer and visually verified equal progress on both edges. Release build succeeds. Navigation and gesture thresholds are unchanged.

## Reordering and moving task trees

All 14 core tests pass. Added coverage for sibling reordering in both directions, rejected cross-parent reorder, nested-tree transfer, promotion of a moved subtask, preservation of notes/completion/IDs, invalid destinations, and serialization. Native UI dragging verified root task and detail subtask reordering using direct in-panel handle gestures. The Move menu transferred a five-task tree to another tab; saved JSON confirmed the nested hierarchy and reordered siblings, with the unrelated source task retained. Move controls are outside row selection/drop highlights and have independent hover styling.

Top-level-only move restriction: Move controls are hidden for nested rows and nested detail views. The model rejects subtask transfers without changing data; updated tests verify that root transfers preserve every descendant and parent link.
