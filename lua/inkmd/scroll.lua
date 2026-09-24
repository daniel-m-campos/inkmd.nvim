-- Scrolling that doesn't get stuck. Neovim 0.12 can bounce CTRL-Y/CTRL-E (and the mouse
-- wheel, which uses the same code) back to where it started when a window row of virtual
-- lines sits next to a line hidden with `conceal_lines`, the way reflowed paragraphs,
-- tables and pictures are drawn: scrolldown() moves topline onto the concealed line, which
-- changes which filler rows show without counting them, so the cursor is left below the
-- window and the next redraw scrolls back. Scrolling on from there repeats it: the window
-- is stuck. These buffer-local mappings scroll, re-validate the view, and when it bounced
-- move the cursor off the window edge and try again (what Neovim's own anti-stuck loop
-- does, but only with 'scrolloff' set and before the view is re-validated).
local state = require('inkmd.state')

local M = {}

local CTRL_Y, CTRL_E = '\25', '\5'
local DESC = 'inkmd: scroll without getting stuck'

--- Whether view `a` is scrolled further up (or down) than view `b`. A bounce can also land
--- on the wrong side of where it started, so direction matters, not just change.
local function scrolled(a, b, up)
  if a.topline ~= b.topline then
    return (a.topline < b.topline) == up
  end
  if a.topfill ~= b.topfill then
    return (a.topfill > b.topfill) == up
  end
  return a.skipcol ~= b.skipcol and (a.skipcol < b.skipcol) == up
end

--- Scroll the current window `count` lines, up (CTRL-Y) or down (CTRL-E).
---@param up boolean
---@param count integer
function M.scroll(up, count)
  local win = vim.api.nvim_get_current_win()
  local key = up and CTRL_Y or CTRL_E
  local before = vim.fn.winsaveview()
  local function try()
    vim.cmd('normal! ' .. count .. key)
    -- Recompute the view the way the next redraw will; this is when a bounce happens.
    vim.api.nvim__redraw({ win = win, valid = false })
    return scrolled(vim.fn.winsaveview(), before, up)
  end
  if try() then
    return
  end
  -- Nothing to scroll: at the top, or the last line is already at the top.
  if (up and before.topline == 1) or (not up and before.topline >= vim.fn.line('$')) then
    vim.fn.winrestview(before)
    return
  end
  -- Start each retry from the original view (a bounce can land past it) with the cursor
  -- i lines further from the edge it was pinned to.
  local last = vim.fn.line('$')
  for i = 1, vim.api.nvim_win_get_height(win) do
    local lnum = up and before.lnum - i or before.lnum + i
    if lnum < 1 or lnum > last then
      break
    end
    vim.fn.winrestview(before)
    -- k and j keep the cursor column and the jumplist.
    vim.cmd('normal! ' .. i .. (up and 'k' or 'j'))
    if try() then
      return
    end
  end
  vim.fn.winrestview(before)
end

local function wheel_lines()
  return tonumber(vim.o.mousescroll:match('ver:(%d+)')) or 3
end

local maps = {
  { '<ScrollWheelUp>', true },
  { '<ScrollWheelDown>', false },
  { '<C-y>', true },
  { '<C-e>', false },
}

--- Whether `win` shows a rendered buffer.
local function rendered(win)
  local st = state.get(vim.api.nvim_win_get_buf(win))
  return st ~= nil and st.enabled
end

---@param buf integer
function M.map(buf)
  for _, spec in ipairs(maps) do
    local lhs, up = spec[1], spec[2]
    local wheel = lhs:match('Wheel') ~= nil
    -- Leave the user's own mappings alone.
    if vim.fn.maparg(lhs, 'n') == '' then
      vim.keymap.set('n', lhs, function()
        local win = vim.api.nvim_get_current_win()
        if wheel then
          -- The wheel scrolls the window under the mouse, not necessarily this one.
          local pos = vim.fn.getmousepos()
          win = vim.api.nvim_win_is_valid(pos.winid) and pos.winid or win
        end
        local count = wheel and wheel_lines() or vim.v.count1
        if count == 0 then
          return
        end
        if rendered(win) and vim.api.nvim_win_get_config(win).relative == '' then
          vim.api.nvim_win_call(win, function()
            M.scroll(up, count)
          end)
        else
          vim.api.nvim_feedkeys(vim.keycode((wheel and '' or count) .. lhs), 'n', false)
        end
      end, { buffer = buf, desc = DESC })
    end
  end
end

---@param buf integer
function M.unmap(buf)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, 'n')) do
    if map.desc == DESC then
      pcall(vim.keymap.del, 'n', map.lhs, { buffer = buf })
    end
  end
end

return M
