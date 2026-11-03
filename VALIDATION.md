# Validation

Tested on Apple Silicon, macOS 27.2, with Xcode 27.2 on November 2, 2026. Build with `./scripts/build.sh`; run the core suite with `./scripts/test.sh`.

## Automated checks

All seven Swift Testing tests pass:

- Nested tasks stay in their own tab; deleting a parent removes all descendants and preserves unrelated tasks.
- Deleting tabs maintains a valid selection and leaves an empty Inbox when deleting the last tab.
- Search includes tab names, nested tasks, parent context, Markdown source, and completed items.
- Atomic JSON persistence round-trips Unicode, notes, completion state, and selected tab.
- Corrupt data and newer formats are rejected without changing the original file.
- Parent cycles and orphaned tasks are rejected.
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

Runtime verification was on the machine above. The macOS 14–15 material fallback, other keyboard layouts, external-monitor configurations, and Stage Manager were not available in this test session. The hotkey uses the ANSI semicolon key position, documented in the README. The bundle is locally signed for personal use, not notarized for distribution.
