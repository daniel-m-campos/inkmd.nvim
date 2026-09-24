local h = require('helpers')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

--- Highlight groups of the marks covering (row, col), 0-based.
local function groups_at(row, col)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, h.ns, { row, 0 }, { row, -1 }, { details = true })) do
    local d = m[4]
    if d.hl_group and m[3] <= col and col < d.end_col then
      out[#out + 1] = d.hl_group
    end
  end
  return out
end

describe('checkboxes', function()
  it('draws custom states with their icons', function()
    h.scratch({ '# x', '', '- [/] doing', '- [-] dropped', '- [>] later', '- [!] now', '- [?] maybe', '- [~] unknown' }, { 1, 0 })
    local screen = h.screen()
    h.eq(screen[3], '\u{f0856} doing')
    h.eq(screen[4], '\u{f0158} dropped')
    h.eq(screen[5], '\u{f0736} later')
    h.eq(screen[6], '\u{f0ce4} now')
    h.eq(screen[7], '\u{f078b} maybe')
    -- Not a configured state: a plain bullet.
    h.eq(screen[8], '● [~] unknown')
    h.truthy(vim.tbl_contains(groups_at(3, 8), 'InkmdTodoCancelledText'), 'cancelled text is struck through')
  end)

  it('takes a checkbox after an ordered marker', function()
    h.scratch({ '# x', '', '1. [x] done', '2. [ ] open' }, { 1, 0 })
    local screen = h.screen()
    h.eq(screen[3], '1. 󰱒 done')
    h.eq(screen[4], '2. 󰄱 open')
  end)

  it('shows the progress of sub-tasks', function()
    h.scratch({
      '# x',
      '',
      '- [/] parent',
      '  - [x] one',
      '  - [/] two',
      '  - [ ] three',
      '  - [-] dropped',
      '- plain parent',
      '  - [x] a',
      '  - [x] b',
      '- no tasks',
      '  - child',
    }, { 1, 0 })
    local screen = h.screen()
    -- Cancelled items don't count.
    h.eq(screen[3], '\u{f0856} parent 1/3')
    h.eq(screen[8], '● plain parent 2/2')
    h.eq(screen[11], '● no tasks')
    -- Kept while the item is raw.
    move(3)
    h.eq(h.screen()[3], '- [/] parent 1/3')
  end)
end)
