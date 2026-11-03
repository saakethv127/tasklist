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

The menu-bar checklist icon also toggles the panel. Right-click it to quit. The app has no Dock icon. To start it automatically, add Tasklist in **System Settings → General → Login Items**.

## Everyday use

- Type in **Add a task…** and press Return. Arrow keys select tasks when that field is empty; Return opens the selection.
- Click a task to edit its title, description, and subtasks. Subtasks are indented with a branching arrow and can have their own subtasks and descriptions. Completing a parent leaves each child's completion state independent.
- Descriptions support `**bold**`, `*italic*`, `[links](https://example.com)`, inline code, headings, and simple lists. Use **Edit / Done** to switch between Markdown and its rendered preview.
- Each tab has an independent list. Right-click a tab to rename or delete it. The ellipsis menu also contains these actions.
- New tabs open the appearance picker after you enter a name. Press **⌘⇧A**, click the palette button beside the tabs, choose **Tab appearance…** in the ellipsis menu, or right-click any tab → **Appearance…**. Choose a preset or **Custom color…** for the standard macOS color panel, plus a searchable collection of 2,019 bundled Lucide SVG icons. Search by name, keyword, or category; press Return to select the first result. Changes save automatically per tab and also identify tabs in global search. The header stays neutral.
- Search covers tab names, task and subtask titles, descriptions, and parent context, including completed tasks.
- Every task, subtask, and tab deletion requires confirmation. Deleting a parent removes its descendants; the prompt tells you how many. **Undo last deletion** in the ellipsis menu restores removed items without discarding subsequent edits. Undo is available for the current app session.
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
| ⌘⌥← | Back to parent task or tab list |
| ⌘⌥→ | Open the selected task from the list |
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

The app stays resident while hidden for fast toggling. It has no recurring timers. Its only scheduled work is a short save debounce after data changes. The bundle is locally signed for personal use; distributing it to other Macs would require Developer ID signing and notarization.

Lucide icons and search metadata are bundled locally; the picker makes no network requests. Upstream attribution is included in `Sources/TasklistCore/Resources/Lucide-LICENSE.txt` and the app bundle. Run `python3 scripts/vendor-lucide.py` to reproduce the pinned collection, or pass a full upstream commit SHA to update it. Existing legacy icon selections remain supported.
