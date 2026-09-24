local h = require('helpers')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

describe('parity', function()
  it('renders frontmatter, links, footnotes, entities and quotes', function()
    h.open('parity.md', { 5, 0 })
    h.golden('parity_top', h.screen())
  end)

  it('renders callouts, rules and tables', function()
    h.open('parity.md', { 33, 0 })
    h.golden('parity_bottom', h.screen())
  end)

  it('gives links their destination as a hyperlink', function()
    local buf = h.open('parity.md', { 33, 0 })
    local urls = {}
    for _, m in ipairs(h.marks(buf)) do
      if m[4].url then
        urls[#urls + 1] = m[4].url
      end
    end
    h.truthy(vim.tbl_contains(urls, 'https://neovim.io'), 'inline link')
    h.truthy(vim.tbl_contains(urls, 'https://example.com'), 'reference link and autolink')
    h.truthy(vim.tbl_contains(urls, 'mailto:me@example.com'), 'email autolink')
  end)

  it('shows the table raw while the cursor is in it', function()
    h.open('parity.md', { 33, 0 })
    move(24)
    local screen = h.screen()
    h.truthy(vim.tbl_contains(screen, '|------|:------:|------:|'), 'delimiter row raw')
    h.truthy(not vim.tbl_contains(screen, '┌─────────────┬────────┬───────┐'), 'top border gone')
  end)

  it('shows only the quote paragraph under the cursor raw', function()
    h.scratch({ '> first', '>', '> second', '', 'end' }, { 5, 0 })
    move(1)
    local screen = h.screen()
    h.eq(screen[1], '> first')
    h.eq(screen[3], '▋ second')
  end)

  it('renders a table with cells missing and no outer pipes', function()
    -- (Virtual lines above the first buffer line only show when scrolled, so start at 2.)
    h.scratch({ 'text', 'a | b | c', '--|--|--', 'x | y', '', 'end' }, { 6, 0 })
    local screen = h.screen()
    h.eq(screen[2], '┌───┬───┬───┐')
    h.eq(screen[3], '│ a │ b │ c │')
    h.eq(screen[4], '├───┼───┼───┤')
    h.eq(screen[5], '│ x │ y │   │')
    h.eq(screen[6], '└───┴───┴───┘')
  end)

  it('hides backslash escapes, including escaped pipes in table code spans', function()
    h.scratch({ 'a \\*b\\*', '', '| x | y |', '|---|---|', '| `a\\|b` | c |', '', 'end' }, { 7, 0 })
    local screen = h.screen()
    h.eq(screen[1], 'a *b*')
    h.eq(screen[4], '│ x   │ y │')
    h.eq(screen[6], '│ a|b │ c │')
  end)

  it('highlights ==text== outside code spans only', function()
    local buf = h.scratch({ 'a ==hi== b `==no==`', '', 'end' }, { 3, 0 })
    h.eq(h.screen()[1], 'a hi b ==no==')
    h.truthy(#h.marks_with_hl(buf, 0, 'InkmdHighlight') == 1, 'one highlight')
  end)
end)
