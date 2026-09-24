-- Horizontal rules, frontmatter and HTML comment blocks.
local code = require('inkmd.handlers.code')
local ts = require('inkmd.ts')

local M = {}

---@param ctx inkmd.Ctx
---@param node TSNode thematic_break
---@param cfg inkmd.Config
function M.rule(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)
  local _, col = node:range()
  -- Overlay rather than conceal + inline: concealed text still counts toward wrapping.
  local width = math.max(ctx.avail - col, 1)
  ctx:overlay(s, col, { { string.rep(cfg.rule.char, width), 'InkmdRule' } })
end

---@param ctx inkmd.Ctx
---@param node TSNode minus_metadata | plus_metadata
---@param cfg inkmd.Config
function M.frontmatter(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)
  local lang = node:type() == 'plus_metadata' and 'toml' or 'yaml'
  local label = cfg.frontmatter.label and code.label(lang):gsub(lang .. ' $', cfg.frontmatter.label .. ' ')
  code.box(ctx, s, e - 1 > s and e - 1 or nil, e, 0, label, cfg)
end

---@param ctx inkmd.Ctx
---@param node TSNode html_block
function M.html_block(ctx, node)
  local s, e = ts.row_span(node)
  if ctx:line(s):match('^%s*<!%-%-') then
    ctx:block(s, e)
    for row = s, e - 1 do
      ctx:hl(row, 0, #ctx:line(row), 'Comment')
    end
  end
end

return M
