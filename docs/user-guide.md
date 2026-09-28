# Using Local Note

The app labels are primarily Chinese. This guide uses the same workday as the
README: prepare a weekly meeting, follow up on feedback, and write a reflection.
The README screenshot contains fictional demonstration data, not real work records.

For download requirements and opening the app for the first time, see
[Installation](installation.md#installation) / [安装](installation.md#安装).

## Capture and complete

Open `LocalNote.app`, then click the checklist icon in the macOS menu bar. There
is no Dock icon or main document window. Click **+** to add `准备周会`. Return
adds a peer at the end of a row; inside text it splits at the caret. Click its
checkbox when complete. Changes save automatically; closing the popover does
not delete the day.

To break down the task, press Return at the end of a top-level checkbox, then
Tab on the empty row. It becomes a numbered child. Add `整理上周进展`, press
Return, and add `列出本周优先事项`. Shift-Tab moves back out of the hierarchy.
For the remaining tasks, add `跟进反馈` and `写下今天的复盘` as top-level rows.

## Review the day

Use the header's arrows for adjacent days, or the calendar button for a month
overview. Selecting a date returns to its outline; the header's date button
returns to today. Calendar colors reflect **absolute completed checkbox
counts**, including nested checkboxes. Numbered notes do not count as to-dos.
It is not a completion percentage or a measure of work quality.

## Keyboard and row controls

- Up / Down: move between items. Long text wraps and grows while editing.
- Return: split at the caret, or add a peer after the current subtree at line end.
- Tab / Shift-Tab: indent / outdent. Type `1. ` at the start of an empty row to
  create a numbered row. Return continues the sequence.
- Numbered depth-one children use `1.`, `2.`; depth-two children use `a.`, `b.`.
- Backspace on an empty alphabetic child returns to the next parent-level
  number; on an empty numbered child it returns to a parent-level checkbox.
- Shift-Up / Shift-Down / Shift-click: select consecutive rows. Drag to select
  part or all of multiple lines.
- Command-C / Command-V: copy / paste; app-to-app outline copies retain row
  types, nesting, completion, and strikethrough. Plain text from other apps
  depends on the supported Markdown/list syntax.
- Command-Shift-S: toggle strikethrough for the active or selected items.
- Backspace: normal text editing; an empty row is removed and focus moves back.
- Command-Z / Command-Shift-Z: undo / redo text and structure changes.
- Right-click: completion, hierarchy, row type, strikethrough, and delete.

## Appearance

Open the gear button → **外观**. Choose **跟随系统 / 浅色 / 深色** (System /
Light / Dark), then System Native, Paper, Graphite, or Midnight and one of six
accent colors. **恢复默认** resets the appearance. These choices apply
immediately, persist locally, and are not sent to Notion.

## Optional Notion sync

This is an implemented, experimental integration. The local workday above does
not need it. Start with a dedicated test page and keep an independent backup.

1. Use your own Notion integration token and grant it access only to a dedicated
   test page. Keep a separate backup of any page you care about.
2. Open the gear button, scroll to **Notion 同步**, and enter the page ID or URL
   plus the token. **保存设置** saves configuration; **保存并同步** also starts sync.
3. Local Note reads the page and updates the selected day's date section. Other
   page content is retained by the day-section replacement logic, but the API
   write replaces the full page Markdown. Concurrent edits outside the selected
   day between read and write are not protected by a transactional merge.

The token is stored in Keychain. Day records and base-Markdown sync snapshots
are unencrypted local JSON; page IDs and appearance preferences use local
preferences. Enabling sync transmits page content to Notion.

Opening the popover, manual refresh, a debounced local edit, and network
restoration can trigger sync. There is no background polling: a change made
in Notion while the popover is open needs refresh or reopening. Requests have
a 15-second timeout; network/service errors remain visible.

When both sides changed, sync stops and offers **以 Notion 为准** (discard local
changes for that day and pull remote) or **以本地为准** (replace that remote day
with local content). Both require a click. A truncated remote response stops
sync before a write. There is no automatic conflict merge, collaboration, or
full-fidelity rich-text/attachment round trip. See the [architecture](architecture.md)
and [security policy](../SECURITY.md).

## Local files and backup

`~/Library/Application Support/LocalNote/days/YYYY-MM-DD.json` stores each day;
`LocalNote/sync/` under the same Application Support folder stores sync
snapshots. Quit the app before copying this folder for backup. There is no
built-in backup/restore UI or app-level encryption. Do not commit these files
or private screenshots to the repository.
