---@class inkmd.BufState
---@field enabled boolean
---@field marks inkmd.Mark[]
---@field tick? integer changedtick the marks were built from
---@field range? {[1]: integer, [2]: integer} rows covered by the marks
---@field avail? integer text width the marks were built for
---@field raw? {[1]: integer, [2]: integer} rows currently shown raw
---@field timer? uv.uv_timer_t
---@field augroup? integer

local M = {}

---@type table<integer, inkmd.BufState>
local buffers = {}

---@return inkmd.BufState?
function M.get(buf)
  return buffers[buf]
end

---@return inkmd.BufState
function M.create(buf, enabled)
  buffers[buf] = { enabled = enabled, marks = {} }
  return buffers[buf]
end

function M.remove(buf)
  local st = buffers[buf]
  if st and st.timer then
    st.timer:stop()
    st.timer:close()
  end
  buffers[buf] = nil
end

---@return integer[]
function M.buffers()
  return vim.tbl_keys(buffers)
end

return M
