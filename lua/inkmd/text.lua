-- Rendered text as data: a range of a buffer row turned into styled chunks the way it is
-- displayed (concealed text dropped, inline virtual text inserted, our highlights and the
-- treesitter colours applied), and word wrapping of those chunks. Used to redraw content in
-- virtual lines, e.g. table cells in block mode.
local ts = require('inkmd.ts')

local M = {}

---@alias inkmd.Atom {text: string, hl: string[]}

local hl_query

--- Treesitter highlight groups over [a, b) of `row`, from the markdown_inline highlights
--- query, as a list of {start, end, group}.
local function ts_spans(ctx, row, a, b)
  local parser = ts.parser(ctx.buf)
  if not parser then
    return {}
  end
  if hl_query == nil then
    hl_query = vim.treesitter.query.get('markdown_inline', 'highlights') or false
  end
  if not hl_query then
    return {}
  end
  local spans = {}
  for _, tree in ipairs(ts.inline_trees(parser, row, row)) do
    local root = tree:root()
    for id, node in hl_query:iter_captures(root, ctx.buf, row, row + 1) do
      local sr, sc, er, ec = node:range()
      local s = sr < row and 0 or sc
      local e = er > row and math.huge or ec
      if s < b and e > a then
        spans[#spans + 1] = { math.max(s, a), math.min(e, b), '@' .. hl_query.captures[id] .. '.markdown_inline' }
      end
    end
  end
  return spans
end

--- Styled chunks for [a, b) of `row` as rendered. Call after the handlers that style the row
--- have run (from a deferred function).
---@param ctx inkmd.Ctx
---@return inkmd.Atom[]
function M.atoms(ctx, row, a, b)
  local line = ctx:line(row)
  local hidden, inserts, spans = {}, {}, ts_spans(ctx, row, a, b)
  for _, mark in ipairs(ctx.by_row[row] or {}) do
    local o = mark.opts
    if o.conceal and o.end_col and not o.end_row then
      for i = math.max(mark.col, a), math.min(o.end_col, b) - 1 do
        hidden[i] = true
      end
    elseif o.virt_text_pos == 'inline' and mark.col >= a and mark.col < b then
      inserts[mark.col] = inserts[mark.col] or {}
      for _, chunk in ipairs(o.virt_text) do
        local group = chunk[2]
        table.insert(inserts[mark.col], { text = chunk[1], hl = type(group) == 'table' and group or { group } })
      end
    elseif o.hl_group and o.end_col and mark.col < b and o.end_col > a then
      spans[#spans + 1] = { math.max(mark.col, a), math.min(o.end_col, b), o.hl_group }
    end
  end

  local atoms = {}
  local function push(text, hl)
    local prev = atoms[#atoms]
    if prev and vim.deep_equal(prev.hl, hl) then
      prev.text = prev.text .. text
    else
      atoms[#atoms + 1] = { text = text, hl = hl }
    end
  end

  local col = a
  while col < b do
    for _, insert in ipairs(inserts[col] or {}) do
      push(insert.text, insert.hl)
    end
    -- One UTF-8 character at a time.
    local len = vim.str_utf_end(line, col + 1) + 1
    if not hidden[col] then
      local hl = {}
      for _, span in ipairs(spans) do
        if span[1] <= col and col < span[2] then
          hl[#hl + 1] = span[3]
        end
      end
      push(line:sub(col + 1, col + len), hl)
    end
    col = col + len
  end
  return atoms
end

---@param atoms inkmd.Atom[]
function M.width(atoms)
  local w = 0
  for _, atom in ipairs(atoms) do
    w = w + vim.api.nvim_strwidth(atom.text)
  end
  return w
end

--- Split atoms into words and single spaces, keeping styles.
---@return {atoms: inkmd.Atom[], width: integer, space: boolean}[]
local function tokens(atoms)
  local out = {}
  local word
  for _, atom in ipairs(atoms) do
    local pos = 1
    local text = atom.text
    while pos <= #text do
      local s, e = text:find('%s+', pos)
      local part_end = s and s - 1 or #text
      if part_end >= pos then
        local part = text:sub(pos, part_end)
        word = word or { atoms = {}, width = 0 }
        word.atoms[#word.atoms + 1] = { text = part, hl = atom.hl }
        word.width = word.width + vim.api.nvim_strwidth(part)
      end
      if not s then
        break
      end
      if word then
        out[#out + 1] = word
        word = nil
      end
      out[#out + 1] = { atoms = { { text = ' ', hl = atom.hl } }, width = 1, space = true }
      pos = e + 1
    end
  end
  if word then
    out[#out + 1] = word
  end
  return out
end

--- Longest word, i.e. the narrowest width that avoids breaking words.
---@param atoms inkmd.Atom[]
function M.min_width(atoms)
  local w = 0
  for _, token in ipairs(tokens(atoms)) do
    if not token.space then
      w = math.max(w, token.width)
    end
  end
  return w
end

--- Break a word wider than `width` into pieces of at most `width` cells; the first piece
--- is at most `first` cells (the room left on the current line).
local function split_word(word, width, first)
  local pieces, cur, cur_w = {}, {}, 0
  local limit = first
  for _, atom in ipairs(word.atoms) do
    for _, ch in ipairs(vim.fn.split(atom.text, '\\zs')) do
      local w = vim.api.nvim_strwidth(ch)
      if cur_w + w > limit and (cur_w > 0 or limit < width) then
        limit = width
        pieces[#pieces + 1] = { atoms = cur, width = cur_w }
        cur, cur_w = {}, 0
      end
      local last = cur[#cur]
      if last and last.hl == atom.hl then
        last.text = last.text .. ch
      else
        cur[#cur + 1] = { text = ch, hl = atom.hl }
      end
      cur_w = cur_w + w
    end
  end
  if cur_w > 0 then
    pieces[#pieces + 1] = { atoms = cur, width = cur_w }
  end
  return pieces
end

--- Greedy word wrap into lines at most `width` cells wide.
---@param atoms inkmd.Atom[]
---@param width integer
---@return {atoms: inkmd.Atom[], width: integer}[]
function M.wrap(atoms, width)
  width = math.max(width, 1)
  local lines = {}
  local line = { atoms = {}, width = 0 }
  local function flush()
    -- No trailing space at the end of a wrapped line.
    local last = line.atoms[#line.atoms]
    if last and last.space then
      table.remove(line.atoms)
      line.width = line.width - 1
    end
    lines[#lines + 1] = line
    line = { atoms = {}, width = 0 }
  end
  local function add(token)
    for _, atom in ipairs(token.atoms) do
      line.atoms[#line.atoms + 1] = { text = atom.text, hl = atom.hl, space = token.space }
    end
    line.width = line.width + token.width
  end
  for _, token in ipairs(tokens(atoms)) do
    if token.space then
      if line.width > 0 and line.width < width then
        add(token)
      end
    elseif line.width + token.width <= width then
      add(token)
    else
      if token.width <= width then
        if line.width > 0 then
          flush()
        end
        add(token)
      else
        -- A word that must break anyway starts in the room left on this line.
        local pieces = split_word(token, width, width - line.width)
        for i, piece in ipairs(pieces) do
          add(piece)
          if i < #pieces then
            flush()
          end
        end
      end
    end
  end
  if line.width > 0 or #lines == 0 then
    flush()
  end
  return lines
end

return M
