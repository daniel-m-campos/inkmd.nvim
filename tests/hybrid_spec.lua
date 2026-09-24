local h = require('helpers')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

describe('hybrid', function()
  it('shows the code block under the cursor raw but keeps its background', function()
    local buf = h.open('basic.md', { 21, 0 })
    move(14)
    local screen = h.screen()
    h.eq(screen[13], '```lua')
    h.eq(screen[16], '```')
    h.truthy(#h.marks_with_hl(buf, 13, 'InkmdCode') == 1, 'background kept')
    -- Other blocks stay rendered.
    h.eq(screen[1], '󰲡 Heading one')
  end)

  it('restores the block when the cursor leaves', function()
    h.open('basic.md', { 21, 0 })
    local before = h.screen()
    move(14)
    move(21)
    h.eq(h.screen(), before)
  end)

  it('makes only the list item under the cursor raw', function()
    h.open('basic.md', { 21, 0 })
    move(7)
    local screen = h.screen()
    h.eq(screen[7], '- first item')
    h.eq(screen[8], '  ○ nested item')
    h.eq(screen[9], '󰄱 open task')
  end)

  it('makes the nested item raw without its parent', function()
    h.open('basic.md', { 21, 0 })
    move(8)
    local screen = h.screen()
    h.eq(screen[7], '● first item')
    h.eq(screen[8], '  - nested item')
  end)

  it('shows inline markers raw on the paragraph under the cursor', function()
    h.open('basic.md', { 21, 0 })
    move(3)
    h.eq(h.screen()[3], 'Some text with `inline code`, *emphasis* and **strong** words.')
  end)

  it('renders everything when hybrid is off', function()
    require('inkmd.config').options.hybrid = false
    local ok, err = pcall(function()
      h.open('basic.md', { 14, 0 })
      h.eq(h.screen()[14], '  local x = 1')
      h.truthy(not h.screen()[13]:find('```', 1, true), 'fence hidden')
    end)
    require('inkmd.config').options.hybrid = true
    assert(ok, err)
  end)

  describe('with two windows on the buffer', function()
    --- Row `r` (1-based) of `win` as drawn.
    local function row(win, r)
      vim.cmd('redraw!')
      vim.cmd('redraw!')
      local pos = vim.fn.win_screenpos(win)
      local cells = {}
      for c = pos[2], pos[2] + vim.api.nvim_win_get_width(win) - 1 do
        cells[#cells + 1] = vim.fn.screenstring(pos[1] + r - 1, c)
      end
      return (table.concat(cells):gsub('%s+$', ''))
    end

    it('shows the block raw only in the current window', function()
      h.scratch({ '# One', '', 'text', '', '## Two' }, { 1, 0 })
      local left = vim.api.nvim_get_current_win()
      vim.cmd('vsplit')
      local right = vim.api.nvim_get_current_win()
      vim.api.nvim_win_set_cursor(right, { 5, 0 })
      vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
      h.eq(row(right, 5), '## Two')
      h.eq(row(left, 5), '󰲣 Two')
      -- Only the current window has a raw block.
      h.eq(row(left, 1), '󰲡 One')
      h.eq(row(right, 1), '󰲡 One')

      -- Back in the left window: its cursor's block is raw there, nothing is in the right.
      vim.api.nvim_set_current_win(left)
      h.eq(row(left, 1), '# One')
      h.eq(row(left, 5), '󰲣 Two')
      h.eq(row(right, 5), '󰲣 Two')
      h.eq(row(right, 1), '󰲡 One')
    end)

    it('keeps the block rendered in a window opened without focus', function()
      local buf = h.scratch({ '# One', '', 'text' }, { 1, 0 })
      local win = vim.api.nvim_open_win(buf, false, { split = 'right' })
      vim.wait(100, function()
        return false
      end)
      h.eq(row(0, 1), '# One')
      h.eq(row(win, 1), '󰲡 One')
    end)
  end)
end)
