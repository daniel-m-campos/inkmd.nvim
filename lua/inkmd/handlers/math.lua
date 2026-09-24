-- LaTeX math. A $$...$$ block that is a paragraph on its own is offered to claimers (the image
-- layer typesets it); inline math, and display math nobody claims, becomes Unicode.
local hooks = require('inkmd.hooks')
local latex = require('inkmd.latex')

---@param ctx inkmd.Ctx
---@param node TSNode latex_block
---@param cfg inkmd.Config
return function(ctx, node, cfg)
  local sr, sc, er, ec = node:range()
  local open, close = node:child(0), node:child(node:child_count() - 1)
  if not open or not close or open == close then
    return
  end
  local _, _, _, open_end = open:range()
  local close_row, close_col = close:range()
  local display = open_end - sc == 2

  -- Display math alone in its paragraph: a candidate for a picture.
  local span = ctx.span
  if display and cfg.math.display then
    local first, last = ctx:line(sr), ctx:line(er)
    local alone = span[1] == sr and span[2] == er + 1 and first:sub(1, sc):match('^[%s>]*$') and last:sub(ec + 1):match('^%s*$')
    if alone then
      local source = vim.treesitter.get_node_text(node, ctx.buf):sub(3, -3)
      local claim = hooks.claim({ kind = 'math', buf = ctx.buf, text = vim.trim(source), s = sr, e = er + 1, col = sc }, ctx)
      if claim then
        -- Pending renders and errors keep the TeX source visible above their message.
        hooks.place(ctx, claim, sr, er + 1)
        if claim.mode ~= 'replace' then
          for row = sr, er do
            ctx:hl(row, row == sr and sc or 0, row == er and ec or #ctx:line(row), 'InkmdMath')
          end
        end
        return
      end
    end
  end

  if not cfg.math.inline then
    return
  end
  if sr ~= er then
    -- Multi-line math that stays text: just colour it.
    for row = sr, er do
      local line = ctx:line(row)
      ctx:hl(row, row == sr and sc or 0, row == er and ec or #line, 'InkmdMath')
    end
    return
  end
  local source = ctx:line(sr):sub(open_end + 1, close_col)
  ctx:conceal(sr, sc, ec)
  ctx:inline(sr, sc, { { latex.convert(source), 'InkmdMath' } })
end
