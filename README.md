# inkmd.nvim

Markdown rendered inside the Neovim buffer you are editing. The block under the cursor
shows as raw markdown; everything else stays rendered. It is built to replace
render-markdown.nvim and to add images and Mermaid diagrams (in progress).

## What renders

- **Headings:** an icon per level, a tinted full-width background, setext underlines drawn
  as rules.
- **Code blocks:** a language label and icon, a block background with padding, thin
  borders. This also works inside lists and quotes.
- **Lists:** bullets by nesting level, checkboxes as icons, ordered markers highlighted.
- **Links:**
  - Inline, reference and autolinks show an icon chosen by destination and act as real
    terminal hyperlinks (OSC 8).
  - Also supported: wikilinks (`[[page]]`, `[[page|alias]]`), footnotes as superscripts,
    and images as their alt text.
- **Quotes and callouts:** nested quote bars. GitHub alerts (`> [!NOTE]`) and Obsidian
  callouts get an icon, a title and a colour.
- **Tables:** box-drawn borders, columns aligned using each cell's rendered width, and the
  delimiter row's alignment respected.
- **Other:**
  - Horizontal rules, frontmatter drawn as a box, and `==highlight==`.
  - HTML entities (`&copy;` → ©), and hidden inline HTML comments.

## Requirements

- Neovim 0.12 or newer, which includes the markdown parsers.
- A Nerd Font, for the icons.
- `termguicolors`, for the blended backgrounds (otherwise linked highlight groups are
  used).

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

Turning rendering off restores your window options (`conceallevel` etc.).

## Claimers: images and diagrams

An extension can take over a code block or an image and draw it in reserved virtual lines:

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

- **Hidden text still counts for wrapping** (Neovim #14409). A long line with a hidden URL
  can take an extra, blank screen row. Rules, code fences and table rules are drawn over
  their source instead, so they are not affected.
- **Virtual lines above the first buffer line** only show once the window is scrolled, so a
  table on line 1 has no top border.
- **Marks are per buffer.** Several windows showing one buffer share the raw block and use
  the narrowest window's width.

## Development

```sh
make test          # headless specs with screen goldens (UPDATE=1 rewrites goldens)
make test FILTER=parity
make bench         # p50/p95 on a generated 10k-line document
```

Design notes and measured Neovim behaviour are in `DESIGN.md`.
