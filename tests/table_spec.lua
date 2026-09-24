local h = require('helpers')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

describe('text wrap', function()
  local text = require('inkmd.text')
  local function plain(lines)
    return vim.tbl_map(function(line)
      return table.concat(vim.tbl_map(function(a)
        return a.text
      end, line.atoms))
    end, lines)
  end

  it('wraps at words and drops the space at line ends', function()
    h.eq(plain(text.wrap({ { text = 'one two three four', hl = {} } }, 9)), { 'one two', 'three', 'four' })
  end)

  it('breaks words longer than the line', function()
    h.eq(plain(text.wrap({ { text = 'abcdefghij', hl = {} } }, 4)), { 'abcd', 'efgh', 'ij' })
  end)

  it('keeps styles across wrapped words', function()
    local lines = text.wrap({ { text = 'plain ', hl = {} }, { text = 'code span', hl = { 'X' } } }, 10)
    h.eq(plain(lines), { 'plain code', 'span' })
    h.eq(lines[2].atoms[1].hl, { 'X' })
  end)
end)

describe('table block mode', function()
  it('fits a wide table to the window with wrapped cells', function()
    h.narrow(60)
    h.open('wide.md', { 9, 0 })
    local screen = h.screen(nil, 60)
    h.golden('table_block', screen)
    for _, line in ipairs(screen) do
      h.truthy(vim.fn.strdisplaywidth(line) <= 60, 'wider than the window: ' .. line)
    end
  end)

  it('shows the source while the cursor is in the table', function()
    h.narrow(60)
    h.open('wide.md', { 9, 0 })
    move(4)
    local screen = h.screen(nil, 60)
    h.eq(screen[3], '| Option | Type | Default | Description |')
    h.truthy(not vim.tbl_contains(screen, '┌───────────┬─────────┬─────────┬──────────────────────────┐'), 'grid hidden')
  end)

  it('reflows when the window is resized', function()
    h.narrow(60)
    local buf = h.open('wide.md', { 9, 0 })
    vim.cmd('vertical resize 50')
    require('inkmd').render_now(buf)
    local screen = h.screen(nil, 50)
    h.eq(vim.fn.strdisplaywidth(screen[3]), 50)
  end)

  it('cuts tables taller than the window short', function()
    h.narrow(36)
    h.open('wide.md', { 9, 0 })
    local screen = h.screen(nil, 36)
    local footer = vim.tbl_filter(function(line)
      return line:match('^⋯ %d+ more lines$') ~= nil
    end, screen)
    h.eq(#footer, 1)
  end)

  it('stays inline in a nowrap window', function()
    h.narrow(60)
    vim.wo.wrap = false
    local buf = h.open('wide.md', { 9, 0 })
    vim.wo.wrap = false
    require('inkmd').render_now(buf)
    h.truthy(vim.startswith(h.screen(nil, 60)[4], '│ Option'), 'inline header row')
  end)

  it('keeps tables that fit inline', function()
    h.scratch({ 'x', '| a | b |', '|---|---|', '| 1 | 2 |', '', 'end' }, { 6, 0 })
    h.eq(h.screen()[3], '│ a │ b │')
  end)
end)
