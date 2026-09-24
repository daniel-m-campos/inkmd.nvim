-- Marks are extmark specs collected by handlers and applied in one pass. Each mark records
-- the buffer rows it visually belongs to (`span`) so hybrid mode can hide exactly the marks
-- of the block under the cursor, and whether it survives that (`keep`).
local M = {}

M.ns = vim.api.nvim_create_namespace('inkmd')

---@class inkmd.Mark
---@field row integer
---@field col integer
---@field opts vim.api.keyset.set_extmark
---@field span {[1]: integer, [2]: integer} rows [start, end)
---@field keep? boolean shown even when its block is raw
---@field id? integer extmark id once applied

---@class inkmd.Ctx
---@field buf integer
---@field avail integer smallest text width among windows showing the buffer
---@field marks inkmd.Mark[]
---@field span {[1]: integer, [2]: integer} span assigned to marks added next
local Ctx = {}
Ctx.__index = Ctx

---@param buf integer
---@param avail integer
---@return inkmd.Ctx
function M.new(buf, avail)
  return setmetatable({ buf = buf, avail = avail, marks = {}, span = { 0, 0 } }, Ctx)
end

--- Set the block span for the marks that follow.
function Ctx:block(s, e)
  self.span = { s, e }
end

---@param row integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@param keep? boolean
function Ctx:add(row, col, opts, keep)
  opts.strict = false
  opts.invalidate = true
  opts.undo_restore = false
  self.marks[#self.marks + 1] = { row = row, col = col, opts = opts, span = self.span, keep = keep }
end

--- Hide text in [col, end_col) on one row.
function Ctx:conceal(row, col, end_col)
  self:add(row, col, { end_col = end_col, conceal = '' })
end

--- Insert virtual text at (row, col), pushing the real text right.
---@param chunks [string, string|string[]][]
function Ctx:inline(row, col, chunks, keep)
  self:add(row, col, { virt_text = chunks, virt_text_pos = 'inline' }, keep)
end

--- Draw virtual text at a fixed window column on `row`.
function Ctx:win_col(row, win_col, chunks, keep)
  self:add(row, 0, { virt_text = chunks, virt_text_win_col = win_col }, keep)
end

--- Highlight [col, end_col) on one row.
function Ctx:hl(row, col, end_col, group, keep)
  self:add(row, col, { end_col = end_col, hl_group = group }, keep)
end

--- Highlight the whole screen line of `row`.
function Ctx:line_hl(row, group, keep)
  self:add(row, 0, { line_hl_group = group }, keep)
end

---@param buf integer
---@param marks inkmd.Mark[]
function M.apply(buf, marks)
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, mark in ipairs(marks) do
    mark.opts.id = nil
    local ok, id = pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, mark.row, mark.col, mark.opts)
    mark.id = ok and id or nil
  end
end

---@param mark inkmd.Mark
---@param s integer
---@param e integer
local function intersects(mark, s, e)
  return mark.span[1] < e and s < mark.span[2]
end

--- Remove the non-`keep` marks of rows [s, e).
function M.hide(buf, marks, s, e)
  for _, mark in ipairs(marks) do
    if mark.id and not mark.keep and intersects(mark, s, e) then
      vim.api.nvim_buf_del_extmark(buf, M.ns, mark.id)
    end
  end
end

--- Put back the marks of rows [s, e) removed by `hide`.
function M.show(buf, marks, s, e)
  for _, mark in ipairs(marks) do
    if mark.id and not mark.keep and intersects(mark, s, e) then
      mark.opts.id = mark.id
      pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, mark.row, mark.col, mark.opts)
    end
  end
end

return M
