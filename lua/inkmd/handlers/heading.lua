local ts = require('inkmd.ts')

--- A half-block rule over the blank line `row`, if it is one.
---@param ctx inkmd.Ctx
local function border(ctx, row, char, level)
  if row < 0 or row >= vim.api.nvim_buf_line_count(ctx.buf) or ctx.hidden_rows[row] then
    return
  end
  if ctx:line(row):match('^%s*$') then
    ctx:win_col(row, 0, { { string.rep(char, ctx.avail), 'InkmdH' .. level .. 'Border' } })
  end
end

---@param ctx inkmd.Ctx
---@param node TSNode atx_heading | setext_heading
---@param cfg inkmd.Config
return function(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)
  local opts = cfg.heading

  if node:type() == 'atx_heading' then
    local marker = node:child(0)
    if not marker then
      return
    end
    local level = tonumber(marker:type():match('^atx_h(%d)_marker$'))
    if not level then
      return
    end
    local row, col, _, marker_end = marker:range()
    local line = vim.api.nvim_buf_get_lines(ctx.buf, row, row + 1, false)[1] or ''
    -- Hide the #s and the space after them; the icon takes their place.
    local end_col = line:sub(marker_end + 1, marker_end + 1) == ' ' and marker_end + 1 or marker_end
    ctx:conceal(row, col, end_col)
    local icon = opts.icons[math.min(level, #opts.icons)]
    ctx:inline(row, col, { { icon, { 'InkmdH' .. level .. 'Bg', 'InkmdH' .. level } } })
    if opts.background == 'full' then
      ctx:line_hl(row, 'InkmdH' .. level .. 'Bg')
      if opts.border then
        border(ctx, s - 1, '▄', level)
        border(ctx, e, '▀', level)
      end
    end
    return
  end

  -- Setext: paragraph text on rows s..e-2, underline (=== or ---) on row e-1.
  local underline = node:named_child(node:named_child_count() - 1)
  local level = underline and underline:type() == 'setext_h2_underline' and 2 or 1
  local urow, ucol
  if underline then
    urow, ucol = underline:range()
  end
  if opts.background == 'full' then
    for row = s, e - 1 do
      ctx:line_hl(row, 'InkmdH' .. level .. 'Bg')
    end
    if opts.border then
      border(ctx, s - 1, '▄', level)
      border(ctx, e, '▀', level)
    end
  end
  if urow then
    local text_width = 0
    for _, text in ipairs(vim.api.nvim_buf_get_lines(ctx.buf, s, urow, false)) do
      text_width = math.max(text_width, vim.fn.strdisplaywidth(text))
    end
    local uline = vim.api.nvim_buf_get_lines(ctx.buf, urow, urow + 1, false)[1] or ''
    ctx:conceal(urow, ucol, #uline)
    ctx:inline(urow, ucol, { { string.rep('─', math.max(text_width, 1)), 'InkmdH' .. level } })
  end
end
