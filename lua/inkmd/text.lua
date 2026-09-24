-- Rendered text as data: a range of a buffer row turned into styled chunks the way it is
-- displayed (concealed text dropped, inline virtual text inserted, our highlights and the
-- treesitter colours applied), and word wrapping of those chunks. Used to redraw content in
-- virtual lines, e.g. table cells in block mode.
local ts = require('inkmd.ts')

local M = {}

---@alias inkmd.Atom {text: string, hl: string[], overlay?: boolean}

local hl_query

--- Treesitter emphasis groups on `row` (italic, strong, strikethrough), as a
--- list of {start, end, group}. Cached per render: rows are often split into several
--- ranges (a list prefix and the text).
---@param ctx inkmd.Ctx
local function row_spans(ctx, row)
  ctx.ts_spans = ctx.ts_spans or {}
  local cached = ctx.ts_spans[row]
  if cached then
    return cached
  end
  local spans = {}
  ctx.ts_spans[row] = spans
  local parser = ts.parser(ctx.buf)
  -- A small query rather than the bundled highlights query (large, predicate-heavy, ~0.2 ms
  -- a row): our own marks already style code, links and ==highlights==.
  hl_query = hl_query
    or vim.treesitter.query.parse(
      'markdown_inline',
      '(emphasis) @markup.italic (strong_emphasis) @markup.strong (strikethrough) @markup.strikethrough'
    )
  if not parser then
    return spans
  end
  for _, tree in ipairs(ts.inline_trees(parser, row, row)) do
    for id, node in hl_query:iter_captures(tree:root(), ctx.buf, row, row + 1) do
      local sr, sc, er, ec = node:range()
      spans[#spans + 1] = { sr < row and 0 or sc, er > row and math.huge or ec, '@' .. hl_query.captures[id] .. '.markdown_inline' }
    end
  end
  return spans
end

--- Treesitter spans clipped to [a, b).
local function ts_spans(ctx, row, a, b)
  local out = {}
  for _, span in ipairs(row_spans(ctx, row)) do
    if span[1] < b and span[2] > a then
      out[#out + 1] = { math.max(span[1], a), math.min(span[2], b), span[3] }
    end
  end
  return out
end

--- Styled chunks for [a, b) of `row` as rendered. Call after the handlers that style the row
--- have run (from a deferred function).
---@param ctx inkmd.Ctx
---@return inkmd.Atom[]
---@param plain? boolean skip treesitter colours (ranges without inline markup)
function M.atoms(ctx, row, a, b, plain)
  local line = ctx:line(row)
  local spans = plain and {} or ts_spans(ctx, row, a, b)
  local hidden = {} ---@type {[1]: integer, [2]: integer}[]
  local inserts = {} ---@type table<integer, inkmd.Atom[]>
  -- Segment boundaries: wherever hiding, highlighting or inserted text starts or stops.
  local points = { [a] = true, [b] = true }
  local function point(col)
    if col > a and col < b then
      points[col] = true
    end
  end
  local function insert(col, chunks, overlay)
    inserts[col] = inserts[col] or {}
    for _, chunk in ipairs(chunks) do
      local group = chunk[2]
      table.insert(inserts[col], { text = chunk[1], hl = type(group) == 'table' and group or { group }, overlay = overlay })
    end
    point(col)
  end

  for _, mark in ipairs(ctx.by_row[row] or {}) do
    local o = mark.opts
    if o.conceal and o.end_col and not o.end_row then
      if mark.col < b and o.end_col > a then
        hidden[#hidden + 1] = { mark.col, o.end_col }
        point(mark.col)
        point(o.end_col)
      end
    elseif o.virt_text_pos == 'inline' and mark.col >= a and mark.col < b then
      insert(mark.col, o.virt_text)
    elseif o.virt_text_pos == 'overlay' and mark.col >= a and mark.col < b then
      -- Drawn over the text: hide the characters it covers and show it instead.
      local w = 0
      for _, chunk in ipairs(o.virt_text) do
        w = w + vim.api.nvim_strwidth(chunk[1])
      end
      local col, covered = mark.col, 0
      while covered < w and col < b do
        local len = vim.str_utf_end(line, col + 1) + 1
        covered = covered + vim.api.nvim_strwidth(line:sub(col + 1, col + len))
        col = col + len
      end
      hidden[#hidden + 1] = { mark.col, col }
      point(col)
      insert(mark.col, o.virt_text, true)
    elseif o.hl_group and o.end_col and mark.col < b and o.end_col > a then
      spans[#spans + 1] = { math.max(mark.col, a), math.min(o.end_col, b), o.hl_group }
    end
  end
  for _, span in ipairs(spans) do
    point(span[1])
    point(span[2])
  end

  local cols = vim.tbl_keys(points)
  table.sort(cols)

  local atoms = {}
  local last_key
  local function push(text, hl, overlay)
    local key = table.concat(hl, ',')
    local prev = atoms[#atoms]
    if prev and not overlay and not prev.overlay and key == last_key then
      prev.text = prev.text .. text
    else
      atoms[#atoms + 1] = { text = text, hl = hl, overlay = overlay }
    end
    last_key = key
  end

  for i = 1, #cols - 1 do
    local p, q = cols[i], cols[i + 1]
    for _, atom in ipairs(inserts[p] or {}) do
      push(atom.text, atom.hl, atom.overlay)
    end
    local is_hidden = false
    for _, h in ipairs(hidden) do
      if h[1] <= p and p < h[2] then
        is_hidden = true
        break
      end
    end
    if not is_hidden then
      local hl = {}
      for _, span in ipairs(spans) do
        if span[1] <= p and p < span[2] then
          hl[#hl + 1] = span[3]
        end
      end
      push(line:sub(p + 1, q), hl)
    end
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
  -- Common case (e.g. a line with a hidden URL that fits once rendered): one line as is.
  local total = M.width(atoms)
  if total <= width then
    return { { atoms = atoms, width = total } }
  end
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
