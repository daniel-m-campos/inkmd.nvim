-- Hybrid view: the leaf block under the cursor shows raw markdown; everything else stays
-- rendered. Works on the cached marks, so moving the cursor never re-parses.
local config = require('inkmd.config')
local marks = require('inkmd.marks')
local state = require('inkmd.state')
local ts = require('inkmd.ts')

local M = {}

---@param buf integer
function M.update(buf)
  local st = state.get(buf)
  if not st or not st.enabled or not st.tick then
    return
  end
  -- Marks from an older changedtick sit at stale positions; the pending render fixes it.
  if st.tick ~= vim.api.nvim_buf_get_changedtick(buf) then
    return
  end

  local s, e
  if config.options.hybrid and vim.api.nvim_get_current_buf() == buf then
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    -- Still inside the raw block: leaf blocks don't share rows, so nothing changes.
    if st.raw and st.raw[1] <= row and row < st.raw[2] then
      return
    end
    s, e = ts.leaf_span(buf, row)
  end

  local raw = st.raw
  if raw and s and raw[1] == s and raw[2] == e then
    return
  end
  if raw then
    marks.show(buf, st.marks, raw[1], raw[2])
  end
  if s then
    marks.hide(buf, st.marks, s, e)
    st.raw = { s, e }
  else
    st.raw = nil
  end
end

return M
