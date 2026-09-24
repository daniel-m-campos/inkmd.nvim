-- Pipe tables, inline mode: cells are padded in place so columns line up, pipes become box
-- lines, the delimiter row becomes a rule and virtual lines add top and bottom borders.
-- Editing stays natural because every source character keeps its row.
local hooks = require('inkmd.hooks')
local text = require('inkmd.text')
local ts = require('inkmd.ts')

---@class inkmd.TableRow
---@field row integer
---@field delimiter boolean
---@field segments {[1]: integer, [2]: integer}[] byte ranges between pipes
---@field leading boolean the row starts with a pipe
---@field trailing boolean the row ends with a pipe
---@field pipes integer[] pipe columns

--- Collect a row's pipes and the cell segments between them.
---@param ctx inkmd.Ctx
---@param node TSNode
---@return inkmd.TableRow
local function parse_row(ctx, node)
  local row, start = node:range()
  local line = ctx:line(row)
  local pipes = {}
  for c in node:iter_children() do
    if c:type() == '|' then
      local _, pc = c:range()
      pipes[#pipes + 1] = pc
    end
  end
  local last = #line:gsub('%s+$', '')
  local leading = pipes[1] == start
  local trailing = #pipes > 0 and pipes[#pipes] == last - 1
  local bounds = {}
  if not leading then
    bounds[#bounds + 1] = start - 1
  end
  vim.list_extend(bounds, pipes)
  if not trailing then
    bounds[#bounds + 1] = last
  end
  local segments = {}
  for i = 1, #bounds - 1 do
    segments[i] = { bounds[i] + 1, bounds[i + 1] }
  end
  return {
    row = row,
    delimiter = node:type() == 'pipe_table_delimiter_row',
    segments = segments,
    leading = leading,
    trailing = trailing,
    pipes = pipes,
  }
end

---@param node TSNode pipe_table_delimiter_row
local function alignments(node)
  local aligns = {}
  for cell in node:iter_children() do
    if cell:type() == 'pipe_table_delimiter_cell' then
      local left, right = false, false
      for a in cell:iter_children() do
        left = left or a:type() == 'pipe_table_align_left'
        right = right or a:type() == 'pipe_table_align_right'
      end
      aligns[#aligns + 1] = (left and right) and 'center' or right and 'right' or 'left'
    end
  end
  return aligns
end

--- Border line from `chars` = {left, fill, cross, right}.
local function border(chars, widths, indent)
  local parts = {}
  for i, w in ipairs(widths) do
    parts[i] = string.rep(chars[2], w + 2)
  end
  return string.rep(' ', indent) .. chars[1] .. table.concat(parts, chars[3]) .. chars[4]
end

local function sum(list)
  local total = 0
  for _, v in ipairs(list) do
    total = total + v
  end
  return total
end

--- Column widths that fit `avail`: natural widths if they fit, else each column shrinks
--- toward its longest word in proportion to how much it can give, else (words must break)
--- widths proportional to those longest words.
---@param natural integer[]
---@param minimum integer[]
---@param avail integer
---@return integer[]
local function fit_columns(natural, minimum, avail)
  local total, min_total = sum(natural), sum(minimum)
  if total <= avail then
    return vim.deepcopy(natural)
  end
  local out = {}
  if min_total <= avail then
    local extra, want = avail - min_total, total - min_total
    for i = 1, #natural do
      out[i] = minimum[i] + math.floor(extra * (natural[i] - minimum[i]) / want)
    end
  else
    for i = 1, #natural do
      out[i] = math.max(1, math.floor(avail * minimum[i] / min_total))
    end
  end
  -- Hand out what rounding left over, left to right, to columns that can use it.
  local left = avail - sum(out)
  local i = 1
  while left > 0 and i <= #out do
    if out[i] < natural[i] then
      out[i] = out[i] + 1
      left = left - 1
    else
      i = i + 1
    end
  end
  return out
end

--- Whether any window showing the buffer wraps lines (block mode needs it: a too-wide
--- table in a nowrap window can just be scrolled).
local function wraps(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.wo[win].wrap then
      return true
    end
  end
  return false
end

--- Smallest window height among windows showing the buffer.
local function win_height(buf)
  local height = math.huge
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    height = math.min(height, vim.api.nvim_win_get_height(win))
  end
  return height == math.huge and vim.o.lines or height
end

--- Block mode: hide the source rows and draw the table fitted to the window in virtual
--- lines, with wrapped cells. Returns false when it doesn't apply (the table is drawn
--- inline instead).
---@param ctx inkmd.Ctx
---@param rows inkmd.TableRow[]
---@param natural integer[] natural column widths
---@param aligns string[]
---@param indent integer
---@param cfg inkmd.Config
local function block(ctx, rows, natural, aligns, indent, s, e, cfg)
  local opts = cfg.table
  local ncols = #natural
  local frame = 3 * ncols + 1
  if opts.block == 'never' or ncols == 0 then
    return false
  end
  local fits = indent + sum(natural) + frame <= ctx.avail
  if opts.block ~= 'always' and (fits or not wraps(ctx.buf)) then
    return false
  end
  local avail = ctx.avail - indent - frame
  if avail < ncols then
    return false
  end

  -- Styled cell contents and each column's longest word.
  local minimum = {}
  for i = 1, ncols do
    minimum[i] = 1
  end
  for _, r in ipairs(rows) do
    if not r.delimiter then
      r.atoms = {}
      for i, c in ipairs(r.content) do
        if i <= ncols then
          r.atoms[i] = text.atoms(ctx, r.row, c.a, c.b)
          minimum[i] = math.max(minimum[i], text.min_width(r.atoms[i]))
        end
      end
    end
  end
  -- One very long word shouldn't make every other column break its words: cap each
  -- column's minimum at a fair share of the width.
  local share = math.max(math.floor(avail / ncols), 1)
  for i = 1, ncols do
    minimum[i] = math.min(minimum[i], share)
  end
  local widths = fit_columns(natural, minimum, avail)

  local border_hl = 'InkmdTableBorder'
  local pad = string.rep(' ', indent)
  local function rule(chars)
    return { { pad .. border(chars, widths, 0), border_hl } }
  end
  local function hl_list(...)
    local list = {}
    for _, group in ipairs({ ... }) do
      if type(group) == 'table' then
        vim.list_extend(list, group)
      elseif group then
        list[#list + 1] = group
      end
    end
    return #list > 0 and list or nil
  end

  local lines = { rule(opts.top) }
  local body = 0
  for index, r in ipairs(rows) do
    if r.delimiter then
      lines[#lines + 1] = rule(opts.middle)
    else
      local header = index == 1
      if not header then
        body = body + 1
      end
      local bg = not header and opts.alternate and body % 2 == 0 and 'InkmdTableRowAlt' or nil
      local wrapped, height = {}, 1
      for i = 1, ncols do
        wrapped[i] = text.wrap(r.atoms[i] or {}, widths[i])
        height = math.max(height, #wrapped[i])
      end
      for l = 1, height do
        local chunks = { { pad }, { opts.vertical, border_hl } }
        for i = 1, ncols do
          local line = wrapped[i][l]
          local w = line and line.width or 0
          local space = widths[i] - w
          local align = aligns[i] or 'left'
          local left = align == 'right' and space or align == 'center' and math.floor(space / 2) or 0
          chunks[#chunks + 1] = { string.rep(' ', 1 + left), hl_list(bg) }
          for _, atom in ipairs(line and line.atoms or {}) do
            chunks[#chunks + 1] = { atom.text, hl_list(bg, header and 'InkmdTableHead' or nil, atom.hl) }
          end
          chunks[#chunks + 1] = { string.rep(' ', space - left + 1), hl_list(bg) }
          chunks[#chunks + 1] = { opts.vertical, border_hl }
        end
        lines[#lines + 1] = chunks
      end
    end
  end
  -- Virtual lines above a row scroll only as far as the window is tall, so a taller
  -- drawing is cut short; the source shows in full with the cursor in the table.
  local max = math.max(win_height(ctx.buf) - 3, 4)
  if #lines + 1 > max then
    local hidden = #lines + 1 - (max - 2)
    lines = vim.list_slice(lines, 1, max - 2)
    lines[#lines + 1] = {
      { pad .. string.format('⋯ %d more lines', hidden), 'Comment' },
    }
  end
  lines[#lines + 1] = rule(opts.bottom)
  hooks.place(ctx, {
    key = 'table',
    mode = 'replace',
    on_raw = 'hide',
    lines = function()
      return lines
    end,
  }, s, e)
  return true
end

---@param ctx inkmd.Ctx
---@param node TSNode pipe_table
---@param cfg inkmd.Config
return function(ctx, node, cfg)
  local s, e = ts.row_span(node)
  ctx:block(s, e)
  local rows, aligns = {}, {}
  for child in node:iter_children() do
    local t = child:type()
    if t == 'pipe_table_header' or t == 'pipe_table_row' or t == 'pipe_table_delimiter_row' then
      rows[#rows + 1] = parse_row(ctx, child)
      if t == 'pipe_table_delimiter_row' then
        aligns = alignments(child)
      end
    end
  end
  if #rows < 2 then
    return
  end
  local _, indent = node:range()
  local opts = cfg.table

  -- Column widths depend on other handlers' conceals (inline code, links), so measure after.
  ctx:defer(function()
    -- GFM: `\|` inside a cell is a literal pipe, even in code spans (where the inline
    -- grammar doesn't see it as an escape). Hide those backslashes before measuring.
    for _, r in ipairs(rows) do
      if not r.delimiter then
        local line = ctx:line(r.row)
        for col in line:gmatch('()\\|') do
          local marks = ctx.by_row[r.row] or {}
          local hidden = false
          for _, m in ipairs(marks) do
            hidden = hidden or (m.opts.conceal and m.col <= col - 1 and (m.opts.end_col or 0) > col - 1)
          end
          if not hidden then
            ctx:conceal(r.row, col - 1, col)
          end
        end
      end
    end

    local ncols = #rows[1].segments
    local widths = {}
    for i = 1, ncols do
      widths[i] = 1
    end
    -- Visible width of each segment's trimmed content.
    for _, r in ipairs(rows) do
      r.content = {}
      if not r.delimiter then
        local line = ctx:line(r.row)
        for i, seg in ipairs(r.segments) do
          local text = line:sub(seg[1] + 1, seg[2])
          local lead = #text:match('^%s*')
          local trail = lead == #text and 0 or #text:match('%s*$')
          local a, b = seg[1] + lead, seg[2] - trail
          local w = ctx:visible_width(r.row, a, b)
          r.content[i] = { a = a, b = b, width = w }
          if i <= ncols then
            widths[i] = math.max(widths[i], w)
          end
        end
      end
    end

    if block(ctx, rows, widths, aligns, indent, s, e, cfg) then
      return
    end

    local vertical = { { opts.vertical, 'InkmdTableBorder' } }
    for index, r in ipairs(rows) do
      local line = ctx:line(r.row)
      if r.delimiter then
        -- Overlay, padded to cover the source: concealed text would still count for wrapping.
        local rule = border(opts.middle, widths, 0)
        local cover = vim.fn.strdisplaywidth(line:sub(indent + 1)) - vim.fn.strdisplaywidth(rule)
        ctx:overlay(r.row, indent, { { rule, 'InkmdTableBorder' }, { string.rep(' ', math.max(cover, 0)) } })
      else
        if not r.leading then
          ctx:inline(r.row, r.segments[1][1], vertical)
        end
        for _, pc in ipairs(r.pipes) do
          ctx:overlay(r.row, pc, vertical)
        end
        -- Closing bar and empty cells for rows with fewer cells than the header. They go in
        -- the same mark as the last cell's padding when that ends the line, so the order of
        -- inline marks at one column never matters.
        local last = #line:gsub('%s+$', '')
        local fill = {}
        if not r.trailing then
          fill[1] = vertical[1]
        end
        for i = #r.content + 1, ncols do
          fill[#fill + 1] = { string.rep(' ', widths[i] + 2) .. opts.vertical, 'InkmdTableBorder' }
        end
        for i, c in ipairs(r.content) do
          local seg = r.segments[i]
          local pad = math.max((widths[i] or c.width) - c.width, 0)
          local align = aligns[i] or 'left'
          local left = align == 'right' and pad or align == 'center' and math.floor(pad / 2) or 0
          local right = pad - left
          -- Exactly one space plus the alignment padding on each side of the content.
          if c.a > seg[1] then
            ctx:conceal(r.row, seg[1], c.a)
          end
          ctx:inline(r.row, seg[1], { { string.rep(' ', 1 + left) } })
          if index == 1 and c.b > c.a then
            ctx:hl(r.row, c.a, c.b, 'InkmdTableHead')
          end
          if seg[2] > c.b then
            ctx:conceal(r.row, c.b, seg[2])
          end
          local chunks = { { string.rep(' ', 1 + right) } }
          if i == #r.content and seg[2] == last then
            vim.list_extend(chunks, fill)
            fill = {}
          end
          ctx:inline(r.row, c.b, chunks)
        end
        if #fill > 0 then
          ctx:inline(r.row, last, fill)
        end
      end
    end

    ctx:virt_lines(s, { { { border(opts.top, widths, indent), 'InkmdTableBorder' } } }, true)
    ctx:virt_lines(e - 1, { { { border(opts.bottom, widths, indent), 'InkmdTableBorder' } } })
  end)
end
