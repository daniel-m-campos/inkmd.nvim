local hooks = require('inkmd.hooks')
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

local M = {}

--- Draw a code-style box: background on rows between the fences, the fences replaced by
--- half-block borders, a label on the top one.
---@param ctx inkmd.Ctx
---@param open_row integer row of the opening fence
---@param close_row? integer row of the closing fence (nil if unclosed)
---@param e integer row after the block
---@param indent integer column of the fences
---@param label? string
---@param cfg inkmd.Config
function M.box(ctx, open_row, close_row, e, indent, label, cfg)
  local opts = cfg.code
  local body_end = close_row or e

  -- Width of the widest body line, measured from the fence's column.
  local body_width = 0
  for row = open_row + 1, body_end - 1 do
    body_width = math.max(body_width, vim.fn.strdisplaywidth(ctx:line(row):sub(indent + 1)))
  end
  local avail = ctx.avail - indent
  local width = math.max(opts.min_width, body_width + opts.left_pad + opts.right_pad)
  width = math.max(math.min(width, avail), 1)
  local pad = string.rep(' ', opts.left_pad)

  -- Body rows: background, left margin and right padding survive hybrid mode (keep).
  for row = open_row + 1, body_end - 1 do
    local line = ctx:line(row)
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

  -- Fences: drawn over (overlay) rather than concealed, since concealed text still counts
  -- toward wrapping. The drawing is at least as wide as the fence so none of it shows.
  local function fence(row, chunks, used, fill)
    local need = vim.fn.strdisplaywidth(ctx:line(row):sub(indent + 1))
    local rest = math.max(width - used, need - used, 0)
    if opts.border == 'thin' then
      chunks[#chunks + 1] = { string.rep(fill, math.max(width - used, 0)), 'InkmdCodeBorder' }
      rest = rest - math.max(width - used, 0)
    end
    if rest > 0 then
      chunks[#chunks + 1] = { string.rep(' ', rest) }
    end
    ctx:overlay(row, indent, chunks)
  end

  local chunks, used = {}, 0
  if opts.label and label then
    chunks[1] = { label, 'InkmdCodeInfo' }
    used = vim.fn.strdisplaywidth(label)
  end
  fence(open_row, chunks, used, '▄')
  if close_row then
    fence(close_row, {}, 0, '▀')
  end
end

---@param lang string
function M.label(lang)
  return string.format(' %s %s ', icons[lang] or generic_icon, lang)
end

---@param ctx inkmd.Ctx
---@param node TSNode fenced_code_block
---@param cfg inkmd.Config
function M.render(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)

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
  local close_row = close and (close:range()) or nil

  local body = {}
  for row = open_row + 1, (close_row or e) - 1 do
    body[#body + 1] = ctx:line(row):sub(indent + 1)
  end
  local claim = hooks.claim({ kind = 'code', buf = ctx.buf, lang = lang, text = table.concat(body, '\n'), s = s, e = e }, ctx)
  if claim then
    hooks.place(ctx, claim, s, e)
    return
  end

  M.box(ctx, open_row, close_row, e, indent, lang and M.label(lang), cfg)
end

return M
