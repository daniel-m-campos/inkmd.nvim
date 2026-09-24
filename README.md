# inkmd.nvim

Markdown rendered inside the Neovim buffer you are editing, including images and Mermaid
diagrams. The block under the cursor shows as raw markdown; everything else stays
rendered. It is built to replace render-markdown.nvim.

## What renders

- **Headings:** an icon per level, a tinted full-width background with half-block borders
  over the blank lines around it (`heading.border`), and setext underlines drawn as rules.
- **Code blocks:** a language label and icon, a block background with padding, thin
  borders. This also works inside lists and quotes.
- **Lists:** bullets by nesting level, ordered markers highlighted, and checkboxes as icons
  (after ordered markers too).
  - Custom states: `[-]` cancelled (struck through), `[/]` in progress, `[>]` forwarded,
    `[!]` important and `[?]` question. Add your own under `checkbox.custom`.
  - An item whose sub-list has tasks shows their progress, such as `2/4`. Cancelled and
    forwarded items don't count.
- **Links:**
  - Inline, reference and autolinks show an icon chosen by destination and act as real
    terminal hyperlinks (OSC 8).
  - Also supported: wikilinks (`[[page]]`, `[[page|alias]]`), footnotes as superscripts,
    and images as their alt text.
- **Quotes and callouts:** nested quote bars. GitHub alerts (`> [!NOTE]`) and Obsidian
  callouts get an icon, a title and a colour.
- **Tables:** box-drawn borders, columns aligned using each cell's rendered width, and the
  delimiter row's alignment respected.
  - A table wider than the window (with `wrap` on) is redrawn fitted to it: columns
    shrink toward their longest word, cells word-wrap and keep their inline styling, and
    body rows alternate their background. It reflows when the window is resized.
- **Other:**
  - Horizontal rules, frontmatter drawn as a box, and `==highlight==`.
  - HTML entities (`&copy;` → ©), and hidden inline HTML comments.

- **Images and Mermaid** (kitty, ghostty, herdr):
  - `mermaid` code blocks are replaced by the rendered diagram. With the cursor in the
    block, the source shows with a live preview below it that re-renders after a pause.
    Syntax errors show under the source.
  - Local images (`png`, `jpg`, `gif`, `webp`, `heic`, `svg`) are drawn below their
    paragraph.
  - Elsewhere, diagrams stay code blocks and images show their alt text.

- **Math:** inline `$…$` becomes Unicode (`$\alpha^2 \leq \frac{1}{n}$` → α² ≤ 1/n). A
  `$$…$$` block on its own is typeset with LaTeX (`latex` + `dvipng`) and drawn as a
  centred picture, with the same live preview and inline errors as Mermaid.

Try it on `examples/demo.md`.

## Requirements

- Neovim 0.12 or newer, which includes the markdown parsers.
- A Nerd Font, for the icons.
- `termguicolors`, for the blended backgrounds (otherwise linked highlight groups are
  used) and for images.
- **For images:** a terminal with the kitty graphics protocol and Unicode placeholders
  (kitty, ghostty, herdr); tmux isn't supported.
  - `mmdc` for Mermaid: `npm i -g @mermaid-js/mermaid-cli`.
  - `sips` (built into macOS) or ImageMagick for jpg/gif/webp/heic, and `rsvg-convert`
    for svg.
  - `latex` and `dvipng` (TeX Live or MacTeX) for display math.

## Setup

It's a local checkout during development:

```lua
vim.opt.rtp:prepend(vim.fn.expand '~/work/inkmd.nvim')
vim.cmd.runtime 'plugin/inkmd.lua'
vim.keymap.set('n', '<leader>tm', '<Plug>(InkmdToggle)')
```

It attaches to `markdown` buffers automatically. `require('inkmd').setup(opts)` is optional;
see `lua/inkmd/config.lua` for every option and its default.

## Commands

| Command | Effect |
| --- | --- |
| `:Inkmd [toggle\|enable\|disable]` | Current buffer. |
| `:Inkmd! [toggle\|enable\|disable]` | All buffers, and the default for new ones. |
| `<Plug>(InkmdToggle)` | Toggle the current buffer. |
| `:checkhealth inkmd` | Parsers, options, external tools, terminal graphics. |
| `:InkmdImageRefresh` | Re-render every diagram and send all images again. |
| `:InkmdImageOpen` | Open the diagram at or above the cursor in the system viewer. |

Turning rendering off restores your window options (`conceallevel` etc.).

## Claimers: images and diagrams

Images and Mermaid use this interface, and other extensions can too. An extension can take
over a code block or an image and draw it in reserved virtual lines:

```lua
require('inkmd.hooks').register_claimer({
  kinds = { 'code' },
  claim = function(item)
    if item.lang ~= 'mermaid' then return end
    return {
      key = item.text,
      mode = 'replace', -- or 'below'
      on_raw = 'keep', -- keep the drawing below the source while editing it
      lines = function(avail) return { { { '…', 'Comment' } } } end,
    }
  end,
})
```

Call `require('inkmd').refresh(buf)` when a drawing finishes asynchronously.

## Known limitations

- **Hidden text still counts for wrapping** (Neovim #14409): Neovim wraps a line as if a
  hidden link URL were still there.
  - inkmd works around this for paragraphs, including those in lists and quotes: rows that
    hide text and would wrap are redrawn word-wrapped by their rendered width
    (`reflow = true`). Rules, code fences and table rules are drawn over their source.
  - Headings with long links still wrap early.
  - Reflowed rows are virtual text: search highlights and visual selection show once the
    cursor is in the paragraph (it is then raw).
- **Scrolling next to hidden lines** can get stuck in Neovim 0.12. inkmd maps the mouse
  wheel, `<C-y>` and `<C-e>` in rendered buffers (normal mode, unless you've mapped them)
  to scroll around it (`fix_scroll = true`). Other scroll commands, and scrolling in
  visual or insert mode, can still stick.
- **Tables taller than the window, once fitted,** are cut short with a "⋯ N more lines"
  footer: virtual lines only scroll as far as the window is tall. The source shows in full
  with the cursor in the table.
- **Virtual lines above the first buffer line** only show once the window is scrolled, so a
  table on line 1 has no top border.
- **Images are placed per size.** A diagram shown in two windows uses the narrower one's
  size.
- **Marks are per buffer.** Several windows showing one buffer share the raw block and use
  the narrowest window's width.

## Development

```sh
make test          # headless specs with screen goldens (UPDATE=1 rewrites goldens)
make test FILTER=parity
make bench         # p50/p95 on a generated 10k-line document
```

Design notes and measured Neovim behaviour are in `DESIGN.md`.
