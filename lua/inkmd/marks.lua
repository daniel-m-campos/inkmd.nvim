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
---@field deferred fun(ctx: inkmd.Ctx)[] run after every handler (see `defer`)
---@field lines table<integer, string> line cache
---@field by_row table<integer, inkmd.Mark[]> marks by row
---@field leaves table<integer, {[1]: integer, [2]: integer, [3]: string?, [4]: integer?}> leaf span, type and start column by row
---@field hidden_rows table<integer, true> rows hidden with conceal_lines
local Ctx = {}
Ctx.__index = Ctx

---@param buf integer
---@param avail integer
---@return inkmd.Ctx
function M.new(buf, avail)
  return setmetatable(
    { buf = buf, avail = avail, marks = {}, by_row = {}, leaves = {}, hidden_rows = {}, span = { 0, 0 }, deferred = {}, lines = {} },
    Ctx
  )
end

--- Text of buffer row `row` (cached for the duration of a render).
function Ctx:line(row)
  local line = self.lines[row]
  if not line then
    line = vim.api.nvim_buf_get_lines(self.buf, row, row + 1, false)[1] or ''
    self.lines[row] = line
  end
  return line
end

--- Rows [start, end) of the leaf block covering `row` (cached for the duration of a render);
--- just `row` when no leaf block covers it.
function Ctx:leaf(row)
  local span = self.leaves[row]
  if not span then
    local s, e, node = require('inkmd.ts').leaf_span(self.buf, row)
    span = s and { s, e, node:type(), select(2, node:range()) } or { row, row + 1 }
    self.leaves[row] = span
  end
  return span[1], span[2]
end

--- Run `fn` after all handlers, with the block span current at the time of the call. For
--- layout that depends on other handlers' marks (table columns measure concealed text).
---@param fn fun(ctx: inkmd.Ctx)
function Ctx:defer(fn)
  local span = self.span
  self.deferred[#self.deferred + 1] = function()
    self.span = span
    fn(self)
  end
end

function Ctx:run_deferred()
  for _, fn in ipairs(self.deferred) do
    fn()
  end
  self.deferred = {}
end

--- Display width of rows' [col, end_col) as rendered: concealed text removed, inline
--- virtual text added. Complete only once every handler has run (use it from `defer`).
function Ctx:visible_width(row, col, end_col)
  local line = self:line(row)
  local width = vim.fn.strdisplaywidth(line:sub(col + 1, end_col))
  for _, mark in ipairs(self.by_row[row] or {}) do
    local o = mark.opts
    if o.conceal and o.end_col and not o.end_row then
      local a, b = math.max(mark.col, col), math.min(o.end_col, end_col)
      if a < b then
        width = width - vim.fn.strdisplaywidth(line:sub(a + 1, b))
      end
    elseif o.virt_text_pos == 'inline' and mark.col >= col and mark.col < end_col then
      for _, chunk in ipairs(o.virt_text) do
        width = width + vim.fn.strdisplaywidth(chunk[1])
      end
    end
  end
  return width
end

--- Set the block span for the marks that follow.
function Ctx:block(s, e)
  self.span = { s, e }
end

---@param row integer
---@param col integer
---@param opts vim.api.keyset.set_extmark
---@param keep? boolean
---@param first? boolean apply before all other marks (virtual lines above one row are drawn
---  in the order their marks were created)
function Ctx:add(row, col, opts, keep, first)
  opts.strict = false
  opts.invalidate = true
  opts.undo_restore = false
  local mark = { row = row, col = col, opts = opts, span = self.span, keep = keep }
  if first then
    table.insert(self.marks, 1, mark)
  else
    self.marks[#self.marks + 1] = mark
  end
  local list = self.by_row[row]
  if not list then
    list = {}
    self.by_row[row] = list
  end
  list[#list + 1] = mark
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

--- Draw virtual text over the real text at (row, col) without moving it.
function Ctx:overlay(row, col, chunks, keep)
  self:add(row, col, { virt_text = chunks, virt_text_pos = 'overlay' }, keep)
end

--- Highlight [col, end_col) on one row, optionally as a hyperlink (OSC 8).
function Ctx:hl(row, col, end_col, group, keep, url)
  self:add(row, col, { end_col = end_col, hl_group = group, url = url }, keep)
end

--- Virtual lines below `row` (or above it).
---@param lines [string, string|string[]][][]
function Ctx:virt_lines(row, lines, above, keep, first)
  self:add(row, 0, { virt_lines = lines, virt_lines_above = above or nil }, keep, first)
end

--- Hide rows [s, e) entirely. Virtual lines attached to hidden rows are not drawn.
function Ctx:conceal_lines(s, e)
  self:add(s, 0, { end_row = e - 1, conceal_lines = '' })
  for row = s, e - 1 do
    self.hidden_rows[row] = true
  end
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
