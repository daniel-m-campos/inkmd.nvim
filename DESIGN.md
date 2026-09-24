# inkmd.nvim design notes

Facts about Neovim 0.12.5 that the design depends on, each checked by a spike.
Re-run `nvim --headless --clean -l spike/core_spike.lua` after a Neovim upgrade.

## Core rendering (`spike/core_spike.lua`, all pass)

| Check | Result | Consequence |
|---|---|---|
| `virt_lines` on a row hidden by `conceal_lines` | Not drawn | A reserved block hangs `virt_lines_above` on the next visible row (or `virt_lines` below the previous one). |
| `conceal_lines` range `(start, end_row=E, end_col=0)` | Hides row E too | Every row the range touches is hidden. To hide rows S..E-1, end the range on row E-1. |
| Tall `virt_lines_above` block while scrolling with `<C-e>` | Scrolls one row at a time through `topfill` | Blocks scroll smoothly. |
| Same block taller than the window | `topfill` starts at about the window height (21 of 30 rows in a 20-row window) | The top of an over-tall block can never be seen. Cap reserved blocks at `winheight - 3` rows. |
| Extmark `conceal = ''` on the cursor row with `concealcursor = ''` | Shown raw | This is the instant reveal hybrid mode relies on. Tests must keep the cursor off rows they assert on. |
| `conceal = '*'` with `conceallevel = 3` | Replacement hidden too | Always use `conceal = ''` plus an inline `virt_text` replacement. |
| Inline `virt_text` bullet + `breakindent`, `breakindentopt = 'list:-1'`, list `formatlistpat` | Wrapped text hangs under the first word | No wrap-guessing code is needed for list items. |
| Stripping `(#set! conceal ...)` / `conceal_lines` from bundled highlights | 0 left in both languages; query still parses; heading capture intact | Use a lazy pattern `%(#set!%s+conceal%s+".-"%)` so `conceal "\""` is handled. |

## Image layer (`spike/kitty_spike.lua`, run in a real terminal)

Headless smoke test: placeholder rows render as one cell per placeholder, and the
concealed-fence layout shows 5 image rows directly above a visible closing fence.

Results from a real herdr pane: _pending_.
