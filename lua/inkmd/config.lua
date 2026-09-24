local M = {}

---@class inkmd.Config
M.defaults = {
  enabled = true,
  filetypes = { 'markdown' },
  max_file_size = 2 * 1024 * 1024,
  debounce = 60,
  -- Show the block under the cursor as raw markdown while everything else stays rendered.
  hybrid = true,
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
  },
  -- YAML/TOML frontmatter drawn like a code block with this label.
  frontmatter = {
    label = 'frontmatter',
  },
}

---@type inkmd.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
