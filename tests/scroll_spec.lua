local h = require('helpers')

--- A rendered buffer whose paragraphs are hidden and redrawn as virtual lines below the
--- line before them, the layout that trips Neovim's scrolling (see lua/inkmd/scroll.lua).
local function layout()
  local lines = {}
  for i = 1, 40 do
    lines[#lines + 1] = ''
    lines[#lines + 1] = 'paragraph ' .. i .. ' ' .. string.rep('word ', 10)
  end
  local buf = h.scratch(lines, { 1, 0 })
  local ns = vim.api.nvim_create_namespace('inkmd_scroll_spec')
  for row = 1, #lines - 1, 2 do
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_row = row, conceal_lines = '' })
    local virt = {}
    for k = 1, row % 3 + 1 do
      virt[k] = { { 'rendered ' .. k } }
    end
    vim.api.nvim_buf_set_extmark(buf, ns, row - 1, 0, { virt_lines = virt })
  end
  -- In a split: resizing the only window would grow the command line for later tests.
  vim.cmd('split')
  vim.cmd('resize 12')
  return buf
end

local function view()
  local v = vim.fn.winsaveview()
  return v.topline .. '+' .. v.topfill
end

--- Scroll with `step` until the view stops changing; the view it stopped at.
local function scroll_all(step)
  local prev
  for _ = 1, 300 do
    step()
    -- A full redraw re-validates the view, which is where a scroll bounces back.
    vim.cmd('redraw!')
    local now = view()
    if now == prev then
      return now
    end
    prev = now
  end
  return prev
end

describe('scroll', function()
  it('scrolls up to the top with CTRL-Y', function()
    layout()
    vim.cmd('normal! G')
    h.eq(scroll_all(function()
      vim.cmd('normal \25')
    end), '1+0')
  end)

  it('scrolls down to the end with CTRL-E', function()
    layout()
    vim.cmd('normal! gg')
    h.eq(scroll_all(function()
      vim.cmd('normal \5')
    end), vim.fn.line('$') .. '+0')
  end)

  it('scrolls with the mouse wheel', function()
    layout()
    vim.cmd('normal! G')
    local win = vim.api.nvim_get_current_win()
    h.eq(scroll_all(function()
      vim.api.nvim_feedkeys(vim.keycode('<ScrollWheelUp>'), 'mx', false)
    end), '1+0')
    h.eq(vim.api.nvim_get_current_win(), win)
  end)

  it("keeps the user's mappings and removes its own on detach", function()
    vim.keymap.set('n', '<C-e>', '<Nop>')
    local buf = layout()
    h.eq(vim.fn.maparg('<C-e>', 'n', false, true).buffer, 0)
    h.eq(vim.fn.maparg('<C-y>', 'n', false, true).buffer, 1)
    require('inkmd').detach(buf)
    h.eq(vim.fn.maparg('<C-y>', 'n'), '')
    vim.keymap.del('n', '<C-e>')
  end)
end)
