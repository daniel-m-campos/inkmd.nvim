local M = {}

--- Spans for inline nodes come from the leaf block they sit in; the caller sets it.

---@param ctx inkmd.Ctx
---@param node TSNode code_span
function M.code_span(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr == er then
    ctx:hl(sr, sc, ec, 'InkmdCodeInline')
  end
end

---@param ctx inkmd.Ctx
---@param node TSNode code_span_delimiter | emphasis_delimiter
function M.delimiter(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr == er then
    ctx:conceal(sr, sc, ec)
  end
end

--- `\*` shows as `*`: hide the backslash.
---@param ctx inkmd.Ctx
---@param node TSNode backslash_escape
function M.escape(ctx, node)
  local sr, sc = node:range()
  ctx:conceal(sr, sc, sc + 1)
end

--- `==text==` (not part of CommonMark or GFM, so the grammar leaves it as text).
---@param ctx inkmd.Ctx
---@param root TSNode inline root
---@param row integer
function M.highlights(ctx, root, row)
  local line = ctx:line(row)
  local rs, rc = root:range()
  local from = row == rs and rc + 1 or 1
  while true do
    local a, text, b = line:match('()==([^=%s][^=]-)==()', from)
    if not a then
      return
    end
    local node = root:named_descendant_for_range(row, a - 1, row, a - 1)
    local in_code = node and (node:type() == 'code_span' or node:type() == 'code_span_delimiter')
    if not in_code and #text > 0 then
      ctx:conceal(row, a - 1, a + 1)
      ctx:hl(row, a + 1, b - 3, 'InkmdHighlight')
      ctx:conceal(row, b - 3, b - 1)
    end
    from = b
  end
end

return M
