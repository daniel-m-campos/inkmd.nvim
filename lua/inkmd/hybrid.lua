-- Hybrid view: the leaf block under the cursor shows raw markdown; everything else stays
-- rendered. Works on the cached marks, so moving the cursor never re-parses.
local config = require('inkmd.config')
local marks = require('inkmd.marks')
local state = require('inkmd.state')
local ts = require('inkmd.ts')

local M = {}

--- Show the leaf block under the cursor raw, in the current window only (other windows on
--- the buffer keep it rendered, see `marks.hide`).
---@param buf integer
---@param force? boolean rebuild even if the raw block is unchanged (the buffer's windows changed)
function M.update(buf, force)
  local st = state.get(buf)
  if not st or not st.enabled or not st.tick then
    return
  end
  -- Marks from an older changedtick sit at stale positions; the pending render fixes it.
  if st.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
    return
  end

  local raw = st.raw
  local target ---@type {[1]: integer, [2]: integer, win: integer}?
  if config.options.hybrid and vim.api.nvim_get_current_buf() == buf then
    local win = vim.api.nvim_get_current_win()
    local row = vim.api.nvim_win_get_cursor(win)[1] - 1
    -- Still inside the raw block: leaf blocks don't share rows, so nothing changes.
    if not force and raw and raw.win == win and raw[1] <= row and row < raw[2] then
      return
    end
    local s, e = ts.leaf_span(buf, row)
    if s then
      target = { s, e, win = win }
    end
  elseif raw and vim.api.nvim_win_is_valid(raw.win) and vim.api.nvim_win_get_buf(raw.win) == buf then
    -- Another buffer has focus: the block stays raw in the window that was left.
    if not force then
      return
    end
    target = raw
  end

  if not force and raw and target and raw[1] == target[1] and raw[2] == target[2] and raw.win == target.win then
    return
  end
  if raw then
    marks.show(buf, st.marks, raw[1], raw[2])
  end
  if target then
    marks.hide(buf, st.marks, target[1], target[2], target.win)
  end
  st.raw = target
end

return M
