-- Pipe tables, inline mode: cells are padded in place so columns line up, pipes become box
-- lines, the delimiter row becomes a rule and virtual lines add top and bottom borders.
-- Editing stays natural because every source character keeps its row.
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
