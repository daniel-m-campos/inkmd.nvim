-- Reflow: a workaround for Neovim #14409. Concealed text still counts toward wrapping, so a
-- line with a long hidden link URL wraps early, as if the URL were there. Paragraph rows
-- that Neovim would wrap and that hide text are hidden and redrawn in virtual lines,
-- word-wrapped by their rendered width. List bullets, hanging indents and quote bars are
-- kept; with the cursor in the paragraph it shows raw as usual.
local hooks = require('inkmd.hooks')
local text = require('inkmd.text')

local M = {}

--- Every window showing the buffer wraps (in a nowrap window the rows just scroll).
local function all_wrap(buf)
  local wins = vim.fn.win_findbuf(buf)
  for _, win in ipairs(wins) do
    if not vim.wo[win].wrap then
      return false
    end
  end
  return #wins > 0
end

--- The row hides text and Neovim would wrap it.
---@param ctx inkmd.Ctx
local function affected(ctx, row)
  local conceals, extra = false, 0
  for _, mark in ipairs(ctx.by_row[row] or {}) do
    local o = mark.opts
    if o.conceal and o.end_col and not o.end_row then
      conceals = true
    elseif o.virt_text_pos == 'inline' then
      for _, chunk in ipairs(o.virt_text) do
        extra = extra + vim.api.nvim_strwidth(chunk[1])
      end
    end
  end
  if not conceals then
    return false
  end
  local line = ctx:line(row)
  -- Bytes are at least the display width, except for tabs.
  if #line + extra <= ctx.avail and not line:find('\t', 1, true) then
    return false
  end
  return vim.fn.strdisplaywidth(line) + extra > ctx.avail
end

---@param hl string[]
local function group(hl)
  return #hl > 0 and hl or nil
end

--- Virtual lines for rows [a, b) of the paragraph `leaf`, wrapped to the window.
---@param ctx inkmd.Ctx
local function reflow(ctx, leaf, a, b)
  local lines = {}
  for row = a, b - 1 do
    local line = ctx:line(row)
    -- The paragraph's first row starts at the node (after a list marker); later rows after
    -- their indent and quote markers.
    local start = row == leaf[1] and leaf[4] or #line:match('^[%s>]*')
    local prefix = text.atoms(ctx, row, 0, start, true)
    local body = text.atoms(ctx, row, start, #line)
    -- Wrapped lines keep quote bars and indent under the bullet (a hanging indent).
    local hanging = {}
    for _, atom in ipairs(prefix) do
      hanging[#hanging + 1] = atom.overlay and atom
        or { text = string.rep(' ', vim.api.nvim_strwidth(atom.text)), hl = {} }
    end
    local width = math.max(ctx.avail - text.width(prefix), 10)
    for i, wrapped in ipairs(text.wrap(body, width)) do
      local chunks = {}
      local function add(atom)
        local hl = group(atom.hl)
        local last = chunks[#chunks]
        if last and vim.deep_equal(last[2], hl) then
          last[1] = last[1] .. atom.text
        else
          chunks[#chunks + 1] = { atom.text, hl }
        end
      end
      for _, atom in ipairs(i == 1 and prefix or hanging) do
        add(atom)
      end
      for _, atom in ipairs(wrapped.atoms) do
        add(atom)
      end
      lines[#lines + 1] = chunks
    end
  end
  return lines
end

--- Reflow affected paragraph rows in [s, e). Runs after every other handler.
---@param ctx inkmd.Ctx
function M.pass(ctx, s, e)
  if not all_wrap(ctx.buf) then
    return
  end
  local row = s
  while row < e do
    local leaf = ctx.leaves[row]
    if leaf and leaf[3] == 'paragraph' and not ctx.hidden_rows[row] and affected(ctx, row) then
      local a, b = row, row + 1
      while b < leaf[2] and not ctx.hidden_rows[b] and affected(ctx, b) do
        b = b + 1
      end
      ctx:block(leaf[1], leaf[2])
      local lines = reflow(ctx, leaf, a, b)
      -- Lines on a hidden row don't draw: hang them on a visible neighbour (below the
      -- previous row when possible, see hooks.anchor), first among lines above a row.
      local anchor, above = hooks.anchor(ctx, a, b)
      if anchor then
        ctx:conceal_lines(a, b)
        ctx:virt_lines(anchor, lines, above, false, above)
      end
      row = b
    else
      row = row + 1
    end
  end
end

return M
