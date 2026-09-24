-- Block quotes: each `>` becomes a bar, coloured by callout type (GitHub alerts, Obsidian
-- callouts) when the quote starts with [!TYPE].
local ts = require('inkmd.ts')

--- Nesting depth of a block_quote: 1 for top-level quotes.
local function depth(node)
  local d = 0
  local n = node
  while n do
    if n:type() == 'block_quote' then
      d = d + 1
    end
    n = n:parent()
  end
  return d
end

--- Column of the `n`th `>` in the line's quote prefix, or nil.
local function marker_col(line, n)
  local count = 0
  for i = 1, #line do
    local ch = line:sub(i, i)
    if ch == '>' then
      count = count + 1
      if count == n then
        return i - 1
      end
    elseif ch ~= ' ' and ch ~= '\t' then
      return nil
    end
  end
end

---@param ctx inkmd.Ctx
---@param node TSNode block_quote
---@param cfg inkmd.Config
return function(ctx, node, cfg)
  local s, e = ts.row_span(node)
  local d = depth(node)
  local group = 'InkmdQuote'

  -- Callout: "> [!TYPE] optional title" on the first row.
  local first = ctx:line(s)
  local col = marker_col(first, d)
  if col then
    local rest_col = col + 1 + (first:sub(col + 2, col + 2) == ' ' and 1 or 0)
    local kind, fold = first:sub(rest_col + 1):match('^%[!(%a+)%]([+-]?)')
    local callout = kind and cfg.callouts[kind:lower()]
    if callout then
      group = callout.hl
      local tag_end = rest_col + #kind + 3 + #fold
      local has_title = first:sub(tag_end + 1):match('%S') ~= nil
      if has_title and first:sub(tag_end + 1, tag_end + 1) == ' ' then
        tag_end = tag_end + 1
      end
      ctx:block(ctx:leaf(s))
      ctx:conceal(s, rest_col, tag_end)
      ctx:inline(s, rest_col, { { callout.icon .. (has_title and '' or callout.title), group } })
      if has_title then
        ctx:hl(s, tag_end, #first, group)
      end
    end
  end

  for row = s, e - 1 do
    local c = marker_col(ctx:line(row), d)
    if c then
      ctx:block(ctx:leaf(row))
      ctx:overlay(row, c, { { cfg.quote.icon, group } })
    end
  end
end
