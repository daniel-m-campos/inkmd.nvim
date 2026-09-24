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

return M
