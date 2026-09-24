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

## M3: images and Mermaid

The user checked this in a real herdr pane on 2026-09-24 with `examples/demo.md`: the
diagrams, the live preview, the error lines and the PNG/SVG images all work.


- **Flow:** the claimer (`lua/inkmd/image/init.lua`) turns ` ```mermaid ` blocks and
  `![](local file)` into claims.
  - Conversions run through `image/pipeline.lua`: deduplicated by content key, at most 2
    jobs at a time, and cached on disk as `stdpath('cache')/inkmd/img/<sha256>.png`.
  - When a job finishes, `inkmd.refresh(buf)` redraws the buffer.
- **Placement:** placeholders are virtual lines of `U+10EEEE` + row/column diacritics. The
  foreground (`InkmdImage<id>`) carries the 24-bit image id.
  - Each (png, cols, rows) gets its own id and one virtual placement
    (`a=p,U=1,c,r,C=1`).
  - Transfers are chunked base64 (`t=d`, 4096 bytes, `q=1`), queued, and drained 32
    chunks per tick through `nvim_ui_send`.
- **Sizing:** the cell size comes from `TIOCGWINSZ` via FFI (16×34 px in herdr), falling
  back to 8×16. Pictures keep their natural pixel size, capped at `max_width`,
  `max_height` and the window height − 3.
  - Mermaid is rendered once at `-s 2`. Width isn't part of the key, so resizing never
    re-runs mmdc.
- **Live preview:** a block keeps its last good picture, keyed by buffer and start row.
  - While edited source re-renders (after `debounce` = 800 ms), the old picture stays, so
    the layout doesn't jump.
  - A first render shows `⋯ rendering mermaid…` under the code block. Errors (the mmdc
    message without ANSI codes or stack trace) show as up to three `DiagnosticError`
    lines.
- **Detection runs on every claim, not once.** During startup no UI may be attached yet
  and `termguicolors` isn't settled, so a UIEnter autocmd re-renders once the TUI attaches.
  - herdr leaks the outer terminal's `TERM_PROGRAM=iTerm.app`, so `HERDR_ENV` is checked
    first.
- **Cleanup:** our ids are deleted (never `d=A`) on `VimLeavePre` and `:InkmdImageRefresh`.
  An `ENOENT` reply for one of our ids re-sends that image.
- **Converting other formats:** `sips` converts without `-Z`, which would also enlarge
  small images. Results over `max_pixels` are shrunk in a second pass.
- **Tests:** a fake `mmdc` script (`tests/fixtures/fake-mmdc`) writes a fixture PNG, or an
  mmdc-style coloured error when the source contains "error". Tests force
  `backend='kitty'` and capture `kitty.write`.

## M4: tables in block mode

- **When it applies:** a table whose natural width (plus its frame) exceeds the window,
  in a window with `wrap` on. `table.block` can force `'always'` or `'never'`.
  - It is placed like a `mode='replace', on_raw='hide'` claim: `conceal_lines` over the
    source, and the grid as `virt_lines_above` on the next row. With the cursor in the
    table, the source shows raw.
- **Rendered text as data:** `text.atoms()` rebuilds a cell as it is displayed.
  - It drops concealed bytes, inserts inline virtual text such as icons, and applies our
    `hl_group` marks plus the `markdown_inline` highlights captures.
  - `text.wrap()` word-wraps those styled atoms. A word that must break starts in the room
    left on the current line.
- **Column fitting:**
  - Natural widths if they fit.
  - Otherwise each column shrinks toward its longest word, capped at a fair share
    (avail ÷ columns) so one long word doesn't break every other column. The shrink is
    proportional to how much each column can give.
  - Otherwise widths are proportional to those minimums. Leftovers go left to right.
- **Height:** drawings taller than the window − 3 are cut short with a `⋯ N more lines`
  footer. `virt_lines_above` only scrolls through about one window height.
- **Window sizes:** `nvim_win_get_width()`/`get_height()` replace `getwininfo().width`,
  which is stale until the next redraw.
  - Headless: setting `columns` doesn't resize the grid's window. Tests narrow a window
    with `:vsplit` plus `:vertical resize` (`h.narrow`).
- **Headless screen reads need two `redraw!`s.** The first fires
  `WinScrolled`/`WinResized`, which re-render. Before this, some screen goldens captured a
  stale grid; `parity_top` now shows the real #14409 wrapping of lines with long hidden
  URLs.

## M5: reflow (a workaround for #14409)

- **Which rows:** paragraph rows that hide text and that Neovim would wrap (raw width plus
  inline virtual text > avail) are hidden with `conceal_lines`. They are redrawn in
  `virt_lines` word-wrapped by their rendered width (`text.atoms` + `text.wrap`).
  - Only when every window showing the buffer wraps.
  - Runs of consecutive rows hang below the previous visible row (`hooks.anchor`), or
    above the next one at the top of the buffer (created `first` so they come before
    other lines there: virtual lines above one row draw in creation order).
- **Prefixes:** the prefix before the paragraph text (bullet, checkbox, quote markers) is
  kept on the first line. Wrapped lines get a hanging prefix: quote-bar overlays are kept
  and everything else becomes spaces.
  - `text.atoms` understands overlays: they hide the cells they cover.
- **Leaf cache:** `ts.leaf_span` returns the node, so `ctx:leaf()` caches the leaf type and
  start column too. The quote handler fills the cache before the paragraph's own capture.
- **Cost:** about 0.15 ms per reflowed row.
  - `text.atoms` uses a three-pattern emphasis query instead of the bundled
    `markdown_inline` highlights query (large and predicate-heavy, about 0.2 ms a row). Our
    marks already style code and links.
  - `text.atoms` works in segments between span/conceal/insert boundaries, and `text.wrap`
    returns early when the row fits.
- **Benchmark:** the document now has a long-link line per section. Render is about
  3.1 ms at p50 and 6 ms at p95 (GC); edit is about 3.5 ms at p50.

## M5: math

- **Parsing:** `markdown_inline` already parses `$…$` and `$$…$$` as `latex_block`. There is
  no bundled LaTeX parser, so there are no colours.
- **Display math:** a `$$` block that is its whole paragraph becomes a `kind='math'` claim.
  The image layer typesets it:
  - `standalone` class with the `preview` option, the configured preamble, and `\color`
    set to Normal's foreground, then `latex -halt-on-error` and
    `dvipng -T tight -bg Transparent`.
  - `dpi = cell_height / 1.2 * 7.2 * scale`, so 10pt TeX is about as tall as the buffer
    text (about 200 dpi on a 34 px cell).
  - The cache key includes the source, preamble, colour and dpi.
  - It is centred in the window, and shares the Mermaid claim logic (`claim_rendered`):
    debounced live preview, previous picture kept, errors (latex's `!` line and `l.N` line)
    under the source.
- **Inline math,** `$$` inside a sentence, and display math when there is no image backend
  go through `inkmd.latex.convert`, a small recursive TeX-to-Unicode converter.
  - Scripts become Unicode super/subscripts only when every character has one;
    otherwise `^(…)`.
  - `\frac` becomes `a/b`, with parentheses only for operands that have a top-level
    operator.
  - Unknown commands are kept as written.
- **Process callbacks:** `vim.system` callbacks run in a fast context, so the steps that
  call Vimscript (mkdir/delete, the next process) are wrapped in `vim.schedule_wrap`.

## Pictures keep their shape

- **The problem:** the user saw display math "squished". Terminals (herdr at least) stretch
  a picture to fill its placement box.
  - The box is whole cells, sized with `ceil`, so short pictures were far off: a formula
    116×31 px got 8×2 cells = 128×68 px, stretched 50% taller (so it looked 50% narrower).
- **The fix (`image/pad.lua`):** when the box's shape differs from the picture's by more
  than 1%, the picture is centred in a transparent PNG of the box's exact pixel size. The
  padded copy is made by wrapping the PNG in an SVG `<image>` and rendering it with
  `rsvg-convert`.
  - It is cached by (png, box px) and produced in the background, showing the unpadded
    picture until it's ready.
  - It applies to Mermaid, math and image files. Without `rsvg-convert`, pictures are sent
    unpadded.

## Scrolling next to hidden lines (a Neovim 0.12 bug)

Touchpad scrolling got stuck in `examples/demo.md`. It reproduces in plain Neovim, without
inkmd (headless, `redraw!` after each step):

- **Layout:** a row of virtual lines next to a line hidden with `conceal_lines`, which is
  how reflowed paragraphs, block tables and pictures are drawn. Conceal alone, or virtual
  lines alone, never stick.
- **Where it breaks:** `scrolldown()` (CTRL-Y, and the wheel) moves topline up one line,
  then "adjusts for concealed lines above w_topline" by moving topline onto the concealed
  line. That changes which filler rows are drawn, but they aren't counted, so the cursor
  correction is off. The next `update_topline` puts the cursor back in the window by
  scrolling back: the view doesn't move, or lands on the other side of where it started.
  Scrolling again repeats it.
- **No placement avoids it.** A sweep over window heights 6 to 40 and both directions:
  - lines below the previous row, or above the next row: both stick;
  - lines on the hidden row itself (below or above): never drawn.
- **'scrolloff' doesn't help.** `scroll_redraw()`'s own "at least move the cursor" loop
  only runs with 'scrolloff' > 0, and it checks before the view is re-validated.
- **The fix (`lua/inkmd/scroll.lua`, `fix_scroll = true`):**
  - Buffer-local normal-mode mappings for `<ScrollWheelUp>`/`<ScrollWheelDown>`
    (`'mousescroll'` lines, in the window under the mouse) and `<C-y>`/`<C-e>`. The
    user's own mappings are left alone.
  - Each scroll runs the builtin command, then re-validates the view with
    `nvim__redraw({win, valid = false})`. That is cheaper than `redraw!` and doesn't
    flush, but it is where the bounce happens.
  - If the view didn't move the right way, it restores the view, moves the cursor `i`
    lines away from the window edge (`i = 1..height`) and tries again.
  - Cost: about 0.8 ms a step (the builtin is 0.03 ms).
  - `tests/scroll_spec.lua` fails without the fix.
- **Anchoring:** still below the previous visible row. In a minimal repro, above-anchoring
  also made the view oscillate. With a `keep` claim (Mermaid live preview) the lines are
  drawn twice:
  - a normal mark at the anchor while rendered;
  - a raw-only mark (`keep = 'raw'`, set only while the block is raw) below the source,
    so the preview sits under the code being edited.
