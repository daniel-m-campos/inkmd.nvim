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

Results from a real herdr pane (2026-09-24, herdr 0.9.1, nvim 0.12.5). The user
confirmed the test images looked good.

- **Probe:**
  - XTVERSION returns `libghostty` (herdr's own emulator).
  - The kitty `a=q` query returns `OK` before the DA1 reply, so the probe order works.
  - Replies arrive through `TermResponse`, as planned.
- **Environment:** `HERDR_ENV=1` and `HERDR_PANE_ID` are set.
  - `TERM_PROGRAM=iTerm.app` leaks in from the outer terminal, and `GHOSTTY_*` and
    `KITTY_WINDOW_ID` are empty.
  - So detection must key on `HERDR_ENV` and the probe, never on `TERM_PROGRAM`.
- **Cell size:** the FFI `TIOCGWINSZ` works on fds 0–2 (`/dev/tty` open fails).
  - It reports 1440×1734 px for 90×51 cells, i.e. 16×34 px cells (a height/width ratio of
    2.125).
- **Transfer:** direct (`t=d`, 2 chunks), file (`t=f`) and temp-file (`t=t`) sends were
  all accepted, and placement with `U=1` Unicode placeholders works.
  - Which methods actually painted wasn't recorded per method, so the default stays
    `t=d`, the method that avoids herdr #732.

## Performance (M1, `make bench`, 10k lines)

- **Injection parsing costs about 17–20 ms per edit, whatever the range.**
  - After any edit, `parser:parse({s, e})` spends that time in Neovim's injection
    bookkeeping across every `markdown_inline` tree (about 4k trees).
  - The built-in highlighter pays the same cost on the redraw after each keystroke. The
    debounced render then finds the tree current, and costs about 1 ms.
- **Unforced renders use `parse(range, on_parse)`.** Neovim then parses in slices of about
  3 ms and calls back synchronously when the tree is already valid.
  - Attach, the debounced edit render and scrolling take this path, so FileType returns in
    about 5 ms. The first paint lands roughly 40 ms later.
  - Forced renders (`render_now`, toggle) stay synchronous, so tests and commands see a
    settled buffer.
- **`leaf_span` starts from `named_descendant_for_range` and walks up** to the nearest
  leaf or `section`. It no longer scans the root's children. Hybrid moves inside the raw
  block return immediately. The p95 is about 0.03 ms.

## M2 findings

- **Overlay beats conceal plus inline for full-width drawings.** Hidden text still counts
  toward wrap width (#14409), so hiding `***` and inserting an 80-column rule wraps onto an
  empty row. Rules, code fences, frontmatter fences and the table delimiter row are drawn
  with `virt_text_pos='overlay'`, padded to cover the source.
- **Inline marks at the same column** don't keep insertion order. The table's closing bar
  shares one mark with the last cell's padding.
- **`virt_lines_above` on buffer line 1** is only visible once the window is scrolled
  (topfill). This affects a table's top border on line 1.
- **`conceal_lines` blocks are reachable.** `j`/`k` land on hidden rows, and hybrid then
  reveals them, so a claim with `mode='replace'` stays editable by normal motion.
- **Finding the injected trees for a range.** Calling `tree:root()` on each of about 4k
  `markdown_inline` trees allocated about 800 KB per render.
  `LanguageTree:included_regions()` is ordered by document position and indexed like
  `trees()`, so `ts.inline_trees` binary-searches it instead.
- **Parse only the visible rows after an edit.** Neovim's own injection parse costs about
  20–50 ms per keystroke on a 10k-line document. Any range the highlighter didn't just
  parse would pay that again, so the render parses only the rows the highlighter covered.
  Margin rows reuse their edited trees, and the next scroll parses them.
- **Render p95 sits near 5 ms, mostly Lua GC pauses.** A render allocates about 380 KB, and
  a full collection walks the parser's heap. The p50 is about 2.2 ms.
- **The benchmark's edits append to paragraph lines.** Inserting at column 0 turns fences
  into text and re-parses the whole document every iteration, which isn't what typing
  does.
