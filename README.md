# Tasklist

A small, local macOS task list that stays out of your way. Press **⌘⌥;** to show or hide a 400 × 560-point glass panel in the bottom-left corner of the display under your pointer. It floats across desktop Spaces without activating a separate app or switching desktops.

Native SwiftUI + AppKit. No web view, server, account, analytics, dependencies, or background polling. macOS 26+ uses Apple's Liquid Glass; macOS 14–15 uses native translucent material.

The pane uses a dark, neutral black-and-white appearance with a flat translucent tint over a blurred backdrop. Only the background is translucent, keeping app text crisp without leaking sharp desktop text through the window. Each tab can have its own accent color and SVG icon.

## Build and run

Requires Xcode 26 or later, selected with `xcode-select`. The app runs on macOS 14+.

```sh
git clone https://github.com/saakethv127/tasklist.git
cd tasklist
./scripts/install.sh
```

This builds a release app, signs it locally, installs it to `~/Applications/Tasklist.app`, and launches it. For a build without installation, run `./scripts/build.sh`; the bundle is in `dist/Tasklist.app`.

For native Xcode development, open `Tasklist.xcodeproj`, select the **Tasklist** scheme and **My Mac**, then Run. The shared scheme also supports Instruments profiling. Quit an existing copy first; the app enforces one running instance.

The menu-bar checklist icon also toggles the panel. If the panel has lost membership in the active desktop Space, showing it recreates its native window while keeping the existing task view and data. Right-click it to quit. The app has no Dock icon. To start it automatically, add Tasklist in **System Settings → General → Login Items**.

## Everyday use

- Type in **Add a task…** and press Return. Arrow keys select tasks when that field is empty; Return opens the selection.
- Click a task to edit its title, description, and subtasks. Subtasks are indented with a branching arrow and can have their own subtasks and descriptions. Completing a parent leaves each child's completion state independent.
- Descriptions support `**bold**`, `*italic*`, `[links](https://example.com)`, inline code, headings, and simple lists. Use **Edit / Done** to switch between Markdown and its rendered preview.
- Each tab has an independent list. Right-click a tab to rename or delete it. The ellipsis menu also contains these actions.
- New tabs open the appearance picker after you enter a name. Press **⌘⇧A**, click the palette button beside the tabs, choose **Tab appearance…** in the ellipsis menu, or right-click any tab → **Appearance…**. Choose a preset or **Custom color…** for the standard macOS color panel, plus a searchable collection of 2,019 bundled Lucide SVG icons. Search by name, keyword, or category; press Return to select the first result. Changes save automatically per tab and also identify tabs in global search. The header stays neutral.
- Search covers tab names, task and subtask titles, descriptions, and parent context, including completed tasks.
- Click and drag a task or subtask right to reveal a red trash icon. At 96 points, the icon pops and a supported trackpad gives a haptic tick; release to delete immediately, or pull back below the threshold to cancel. Menu, keyboard, and tab deletions still require confirmation. Deleting a parent removes its descendants; the prompt tells you how many. **Undo last deletion** in the ellipsis menu restores removed items without discarding subsequent edits. Undo is available for the current app session.
- Clicking another app leaves the panel visible. The hotkey or minus button hides it. Escape closes a prompt, search, or task detail first, then hides the list.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘⌥; | Show / hide from any app |
| ⌘K | Search across all tabs, tasks, subtasks, and notes |
| ↑ / ↓, Return | Select / open a search result or task |
| ⌘← / ⌘→ | Previous / next tab, wrapping around |
| ⌘T | New tab, then choose color and icon |
| ⌘⇧A | Open / close current tab appearance |
| ⌘W | Confirm deletion of the current tab |
| ⌘⌥← | Back through task navigation history |
| ⌘⌥→ | Forward through task navigation history |
| ⌘N | Focus task / subtask quick-add field |
| ⌘⌫ | Confirm deletion of the selected / open task |
| Return / Escape | Confirm / cancel a modal |

The global shortcut uses the semicolon's ANSI physical key position; on non-US keyboard layouts the printed character may differ. If another app owns the shortcut, Tasklist shows an error and remains accessible from the menu bar. It does not request Accessibility or Input Monitoring permissions.

## Local data

Tasks are stored in `~/Library/Application Support/Tasklist/tasks.json`. Changes are saved atomically after a 250 ms typing pause and flushed on hide or quit. The ellipsis menu can reveal this file in Finder. Back it up like any other document. Nothing is uploaded to GitHub; the repository contains only app source.

A file that fails decoding or validation is left untouched, and the panel displays an error instead of overwriting it. Do not continue adding tasks in that state; repair or restore the file, then relaunch.

## Development and verification

```sh
./scripts/test.sh
./scripts/build.sh
```

The core tests exercise persistence, invalid data, nested deletion, tab isolation, search, and a 1,000-task search benchmark. See [VALIDATION.md](VALIDATION.md) for runtime checks and performance measurements.

For an isolated manual test session:

```sh
open dist/Tasklist.app --args --data-path /tmp/tasklist-test.json --diagnostics /tmp/tasklist-diagnostics.json
```

Quit any existing Tasklist instance first. `--data-path` separates test data from your actual tasks. `--diagnostics` records the most recent 200 show/hide handler durations plus panel state; it is off by default. These timings measure app-side handling and synchronous display work, not physical key-to-photon latency. `--hidden` starts with the panel hidden.

Window troubleshooting metadata is always recorded locally in the macOS unified log under subsystem `com.saakethv.tasklist`, category `window`. It records shortcut/menu input, show/hide state before and after ordering, a settled check after 250 ms, and Space/display/sleep/wake transitions. Each entry includes the panel's AppKit visibility, active-Space and occlusion state, WindowServer on-screen state, frame, and connected display bounds. It does not record tasks, typed text, or screenshots. Retention is managed by macOS. If the panel becomes invisible, capture these logs **before restarting**:

```sh
/usr/bin/log show --last 1h --style compact \
  --predicate 'subsystem == "com.saakethv.tasklist" AND category == "window"'
```

The app stays resident while hidden for fast toggling. It has no recurring timers. Scheduled work is limited to a short save debounce after data changes and one window-state diagnostic check 250 ms after each show/hide action. The bundle is locally signed for personal use; distributing it to other Macs would require Developer ID signing and notarization.

Lucide icons and search metadata are bundled locally; the picker makes no network requests. Upstream attribution is included in `Sources/TasklistCore/Resources/Lucide-LICENSE.txt` and the app bundle. Run `python3 scripts/vendor-lucide.py` to reproduce the pinned collection, or pass a full upstream commit SHA to update it. Existing legacy icon selections remain supported.

Task rows use compact spacing in lists and details. Click the chevron to the left of a parent task to collapse or expand its subtasks; clicking its title opens details. Nested collapse choices are retained during the app session.

Two-finger horizontal swipes over the task content navigate session history: swipe right for back, left for forward. An edge semicircle and arrow fill with the gesture; reaching the threshold navigates once with a light haptic tick. Short gestures retract, and vertical scrolling stays available. History resets when switching tabs; opening another task after going back replaces the forward branch. The tab strip keeps its own horizontal scrolling.

Drag vertically anywhere on a task’s highlighted surface to reorder it among siblings, in either the main list or a task’s subtask list. Order saves automatically. Only top-level tasks have a separate move icon (or **Move** in detail). Moving one transfers all its descendants to the destination tab and opens it there. Subtasks cannot move independently between tabs.

During reordering, the grabbed row follows the pointer and sibling rows slide aside to preview its new position. Expanded descendants move with their parent. Release to save the order. Task and subtask rows highlight on hover; the separate move control uses the same row height for its own hover highlight.

Drag a tab directly by its name to reorder tabs. Other tabs slide aside during the drag; releasing saves the new order without changing the selected tab. A normal click still switches tabs.

Task rows have no separate drag handle or detail chevron. Click the title/surface to open details; drag vertically to reorder or right to delete. Parent disclosure arrows still expand or collapse subtasks.
