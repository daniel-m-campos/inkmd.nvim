local ts = require('inkmd.ts')

-- Nerd Font (devicons) codepoints for common languages; anything else gets the generic one.
-- Written as escapes because private-use characters are easily lost when files are edited.
local icons = {
  bash = '\u{e795}', c = '\u{e61e}', cpp = '\u{e61d}', css = '\u{e749}', diff = '\u{f440}',
  go = '\u{e627}', html = '\u{e736}', java = '\u{e738}', javascript = '\u{e74e}', js = '\u{e74e}',
  json = '\u{e60b}', lua = '\u{e620}', make = '\u{e779}', markdown = '\u{e609}', md = '\u{e609}',
  python = '\u{e606}', py = '\u{e606}', ruby = '\u{e739}', rust = '\u{e7a8}', sh = '\u{e795}',
  sql = '\u{e706}', toml = '\u{e6b2}', ts = '\u{e628}', typescript = '\u{e628}', vim = '\u{e62b}',
  yaml = '\u{e6a8}', zsh = '\u{e795}',
}
local generic_icon = '\u{f022e}'

---@param ctx inkmd.Ctx
---@param node TSNode fenced_code_block
---@param cfg inkmd.Config
return function(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)
  local opts = cfg.code

  local open, close, lang
  for child in node:iter_children() do
    local t = child:type()
    if t == 'fenced_code_block_delimiter' then
      if not open then
        open = child
      else
        close = child
      end
    elseif t == 'info_string' then
      local language = child:named_child(0)
      if language then
        lang = vim.treesitter.get_node_text(language, ctx.buf)
      end
    end
  end
  if not open then
    return
  end

  local open_row, indent = open:range()
  local close_row = close and close:range() or e
  local lines = vim.api.nvim_buf_get_lines(ctx.buf, open_row, e, false)

  -- Width of the widest body line, measured from the fence's column.
  local body_width = 0
  for i = 2, close and #lines - 1 or #lines do
    body_width = math.max(body_width, vim.fn.strdisplaywidth(lines[i]:sub(indent + 1)))
  end
  local avail = ctx.avail - indent
  local width = math.max(opts.min_width, body_width + opts.left_pad + opts.right_pad)
  width = math.max(math.min(width, avail), 1)
  local pad = string.rep(' ', opts.left_pad)

  -- Body rows: background, left margin and right padding survive hybrid mode (keep).
  for row = open_row + 1, close_row - 1 do
    local line = lines[row - open_row + 1] or ''
    local col = math.min(indent, #line)
    ctx:inline(row, col, { { pad, 'InkmdCode' } }, true)
    if #line > col then
      ctx:hl(row, col, #line, 'InkmdCode', true)
    end
    local used = opts.left_pad + vim.fn.strdisplaywidth(line:sub(col + 1))
    if used < width then
      ctx:win_col(row, indent + used, { { string.rep(' ', width - used), 'InkmdCode' } }, true)
    end
  end

  -- Opening fence: hide ``` and the info string, show a label and/or the top border.
  local open_line = lines[1]
  ctx:conceal(open_row, indent, #open_line)
  local chunks = {}
  local used = 0
  if opts.label and lang then
    local label = string.format(' %s %s ', icons[lang] or generic_icon, lang)
    chunks[#chunks + 1] = { label, 'InkmdCodeInfo' }
    used = vim.fn.strdisplaywidth(label)
  end
  if opts.border == 'thin' and width > used then
    chunks[#chunks + 1] = { string.rep('▄', width - used), 'InkmdCodeBorder' }
  end
  if #chunks > 0 then
    ctx:inline(open_row, indent, chunks)
  end

  -- Closing fence: hide it, draw the bottom border.
  if close then
    local close_line = lines[close_row - open_row + 1]
    ctx:conceal(close_row, indent, #close_line)
    if opts.border == 'thin' then
      ctx:inline(close_row, indent, { { string.rep('▀', width), 'InkmdCodeBorder' } })
    end
  end
end
