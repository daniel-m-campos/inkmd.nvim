local M = {}

---@class inkmd.Config
M.defaults = {
  enabled = true,
  filetypes = { 'markdown' },
  max_file_size = 2 * 1024 * 1024,
  debounce = 60,
  -- Show the block under the cursor as raw markdown while everything else stays rendered.
  hybrid = true,
  -- Redraw paragraph rows that hide text (link URLs, markup) and would wrap, word-wrapped
  -- by their rendered width: Neovim wraps concealed text as if it were visible (#14409).
  reflow = true,
  -- Map the mouse wheel, CTRL-Y and CTRL-E (normal mode, unless already mapped) to scroll
  -- without getting stuck next to hidden lines, a Neovim bug (see lua/inkmd/scroll.lua).
  fix_scroll = true,
  win_options = {
    conceallevel = 3,
    concealcursor = '',
    breakindent = true,
    breakindentopt = 'list:-1',
  },
  heading = {
    icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    -- 'full' paints the whole line, 'none' leaves the background alone.
    background = 'full',
    -- Half-block rules above and below the heading's background, drawn over the blank
    -- lines around it (never adding lines). Needs `background = 'full'`.
    border = true,
  },
  code = {
    left_pad = 2,
    right_pad = 2,
    min_width = 40,
    -- 'thin' draws half-block rules above and below the block; 'none' just hides the fences.
    border = 'thin',
    label = true,
  },
  list = {
    bullets = { '●', '○', '◆', '◇' },
  },
  -- The space after "[ ]" is kept, so icons carry no trailing space.
  checkbox = {
    unchecked = '󰄱',
    checked = '󰱒',
    -- More states, written `- [c] text`. `text_hl` styles the item's text. `progress` is
    -- how the item counts in its parent's progress: 'done', 'todo', or false (not at all).
    custom = {
      ['-'] = { icon = '\u{f0158}', hl = 'InkmdTodoCancelled', text_hl = 'InkmdTodoCancelledText', progress = false },
      ['/'] = { icon = '\u{f0856}', hl = 'InkmdTodoDoing', progress = 'todo' },
      ['>'] = { icon = '\u{f0736}', hl = 'InkmdTodoForwarded', progress = false },
      ['!'] = { icon = '\u{f0ce4}', hl = 'InkmdTodoImportant', progress = 'todo' },
      ['?'] = { icon = '\u{f078b}', hl = 'InkmdTodoQuestion', progress = 'todo' },
    },
    -- Show "done/total" after an item whose sub-list has tasks.
    progress = true,
  },
  -- Icons go before the link text; the first matching destination pattern wins.
  link = {
    icons = {
      link = '\u{f0337} ',
      web = '\u{f059f} ',
      file = '\u{f0219} ',
      email = '\u{f01ee} ',
      image = '\u{f02e9} ',
      wiki = '\u{f0219} ',
    },
    destinations = {
      { pattern = 'github%.com', icon = '\u{f02a4} ' },
      { pattern = 'gitlab%.com', icon = '\u{f0ba0} ' },
      { pattern = 'youtube%.com', icon = '\u{f05c3} ' },
      { pattern = 'youtu%.be', icon = '\u{f05c3} ' },
      { pattern = 'wikipedia%.org', icon = '\u{f05ac} ' },
      { pattern = 'stackoverflow%.com', icon = '\u{f04cc} ' },
    },
    -- Show footnote references such as [^1] as superscripts.
    footnote_superscript = true,
  },
  quote = {
    icon = '▋',
  },
  -- GitHub alerts and Obsidian callouts, keyed by lower-case type.
  callouts = {
    note = { icon = '\u{f02fd} ', title = 'Note', hl = 'InkmdNote' },
    tip = { icon = '\u{f0336} ', title = 'Tip', hl = 'InkmdTip' },
    important = { icon = '\u{f017e} ', title = 'Important', hl = 'InkmdImportant' },
    warning = { icon = '\u{f002a} ', title = 'Warning', hl = 'InkmdWarning' },
    caution = { icon = '\u{f0ce6} ', title = 'Caution', hl = 'InkmdCaution' },
    abstract = { icon = '\u{f0a38} ', title = 'Abstract', hl = 'InkmdNote' },
    summary = { icon = '\u{f0a38} ', title = 'Summary', hl = 'InkmdNote' },
    tldr = { icon = '\u{f0a38} ', title = 'TL;DR', hl = 'InkmdNote' },
    info = { icon = '\u{f02fd} ', title = 'Info', hl = 'InkmdNote' },
    todo = { icon = '\u{f05e1} ', title = 'Todo', hl = 'InkmdNote' },
    hint = { icon = '\u{f0336} ', title = 'Hint', hl = 'InkmdTip' },
    success = { icon = '\u{f012c} ', title = 'Success', hl = 'InkmdTip' },
    check = { icon = '\u{f012c} ', title = 'Check', hl = 'InkmdTip' },
    done = { icon = '\u{f012c} ', title = 'Done', hl = 'InkmdTip' },
    question = { icon = '\u{f0625} ', title = 'Question', hl = 'InkmdWarning' },
    help = { icon = '\u{f0625} ', title = 'Help', hl = 'InkmdWarning' },
    faq = { icon = '\u{f0625} ', title = 'FAQ', hl = 'InkmdWarning' },
    attention = { icon = '\u{f002a} ', title = 'Attention', hl = 'InkmdWarning' },
    failure = { icon = '\u{f0156} ', title = 'Failure', hl = 'InkmdCaution' },
    fail = { icon = '\u{f0156} ', title = 'Fail', hl = 'InkmdCaution' },
    missing = { icon = '\u{f0156} ', title = 'Missing', hl = 'InkmdCaution' },
    danger = { icon = '\u{f140c} ', title = 'Danger', hl = 'InkmdCaution' },
    error = { icon = '\u{f140c} ', title = 'Error', hl = 'InkmdCaution' },
    bug = { icon = '\u{f0a30} ', title = 'Bug', hl = 'InkmdCaution' },
    example = { icon = '\u{f0279} ', title = 'Example', hl = 'InkmdImportant' },
    quote = { icon = '\u{f11a8} ', title = 'Quote', hl = 'InkmdQuote' },
    cite = { icon = '\u{f11a8} ', title = 'Cite', hl = 'InkmdQuote' },
  },
  rule = {
    char = '─',
  },
  table = {
    -- Box-drawing characters: top, middle (under the header) and bottom rows, and the
    -- vertical bar.
    top = { '┌', '─', '┬', '┐' },
    middle = { '├', '─', '┼', '┤' },
    bottom = { '└', '─', '┴', '┘' },
    vertical = '│',
    -- Tables wider than the window (with 'wrap' on) are redrawn fitted to it with wrapped
    -- cells: 'auto'. 'always' draws every table that way, 'never' keeps them inline.
    block = 'auto',
    -- Alternate body row background in block mode.
    alternate = true,
  },
  -- YAML/TOML frontmatter drawn like a code block with this label.
  frontmatter = {
    label = 'frontmatter',
  },
  -- LaTeX math: $inline$ is converted to Unicode (α² ≤ 1/n); a $$display$$ block on its own
  -- is typeset (RaTeX or latex + dvipng) and drawn as a picture (with the image backend).
  math = {
    inline = true,
    display = true,
    -- 'ratex' (RaTeX: KaTeX syntax, about 5 ms a formula), 'latex' (latex + dvipng: any
    -- LaTeX, about 250 ms), or 'auto': RaTeX when installed, latex for what it can't typeset.
    backend = 'auto',
    -- RaTeX's PNG renderer (the `render` binary of its releases), installed as `ratex`.
    ratex = 'ratex',
    latex = 'latex',
    dvipng = 'dvipng',
    preamble = '\\usepackage{amsmath,amssymb}',
    -- Size relative to the buffer text.
    scale = 1.0,
    -- Wait this long after the last edit before typesetting a formula being edited.
    debounce = 500,
    timeout = 30000,
  },
  -- Images and diagrams drawn in the buffer with the kitty graphics protocol (kitty,
  -- ghostty, herdr). Elsewhere they fall back to text.
  image = {
    enabled = true,
    -- 'auto' detects the terminal; 'kitty' forces the graphics protocol; 'text' disables it.
    backend = 'auto',
    -- Largest drawing, in cells. The height is also capped to the window height - 3.
    max_width = 100,
    max_height = 30,
    -- Local image files referenced with ![alt](path). Remote (http) images are not fetched.
    files = true,
    -- Longest image side sent to the terminal, in pixels (larger ones are downscaled).
    max_pixels = 2048,
    mermaid = {
      enabled = true,
      -- 'mmdc' (mermaid-cli: Node and headless Chromium, about 0.5 s a diagram), 'merman'
      -- (merman-cli, a Rust port: output close to mmdc's, about 30 ms), 'mmdr'
      -- (mermaid-rs-renderer: about 20 ms, but its layouts differ and it draws some invalid
      -- diagrams without an error), or 'auto': the first installed of merman, mmdc, mmdr.
      backend = 'auto',
      cmd = 'mmdc',
      merman = 'merman-cli',
      mmdr = 'mmdr',
      -- Code block languages rendered as Mermaid.
      langs = { 'mermaid', 'mmd' },
      -- nil picks 'dark' or 'default' from 'background'.
      theme = nil,
      background = 'transparent',
      scale = 2,
      -- Extra arguments, e.g. { '-c', 'mermaid-config.json' }.
      args = {},
      -- Wait this long after the last edit before re-rendering a diagram being edited.
      debounce = 800,
      timeout = 30000,
      max_jobs = 2,
    },
  },
}

---@type inkmd.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
