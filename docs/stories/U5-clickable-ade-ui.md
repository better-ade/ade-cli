# U5: `ade ui` can be used with the mouse alone

Status: **Approved** (owner, 2026-11-28). Risk: **medium** (new clickable controls that run ade's own
commands; no change to sign-in, keys, sync or what a session may do). Verification: `bash tests/run.sh`.
Owner's intent (2026-11-28): "is there a way the cli can also be clickable for those not familiar with tmux".

## Today
`set -g mouse on` already lets a click on a tab's name in the status bar switch to it, and the new-agent and approve
menus (`display-menu`) take clicks. Nothing on screen says so, and every other action needs a `prefix` key.

## Acceptance criteria (each named by its test, tests/test_ui.sh)
1. **click_buttons**: the status bar shows a short row of buttons, `[+ agent] [tickets] [files] [approve] [dash] [? keys]`,
   drawn as tmux 3.4 ranges (`#[range=user|…]`, read back with `mouse_status_range`); a left click on one does exactly
   what its key does (`prefix n`, `t`, `e`, `a`, `f`, `?`). On a narrow screen (under 100 columns) it shows
   `[+] [≡ menu]` only; on tmux 3.2 and 3.3 it shows `[+] [≡ menu]` at any width.
   Amended 2026-11-28 with the owner's approval: ranges need tmux 3.4.
2. **click_menu**: a click on `[≡ menu]`, or a right click on the status bar, opens one `display-menu` of every ade action
   in the keys popup, each with its key shown beside it, so a click teaches the key.
3. **click_tab_menu**: a right click on a tab's name opens a menu for that tab: go to it, rename (U2), preview its plan,
   links, close it (asks `close api? y/n` first, never on one click).
4. **click_scroll_select**: the wheel scrolls an agent's pane history and a drag selects and copies text (to the
   system clipboard where `clip_copy` works), with no prefix key; the first wheel up in a session shows "scrolling: q
   or Esc to return" once.
5. **click_off**: `ADE_UI_MOUSE=off` (U1) hides the buttons as well, so the bar never shows a control that does nothing.
6. **click_first_run**: the first `ade ui` on a machine shows one line under the bar: "Click a tab or a button; right
   click for every action. Keys: ? keys", until it is dismissed or 3 sessions have passed.
7. **u5_docs**: README ("Use it with the mouse"), `ade help` and CHANGELOG.

## Out of scope
A graphical app, drag-to-reorder tabs, clickable links inside panes (U1 leaves them as they are).
