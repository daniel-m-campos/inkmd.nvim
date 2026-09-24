-- The render pipeline: visible range -> parse -> handlers -> marks -> apply -> hybrid.
local config = require('inkmd.config')
local hybrid = require('inkmd.hybrid')
local marks = require('inkmd.marks')
local state = require('inkmd.state')
local ts = require('inkmd.ts')

local heading = require('inkmd.handlers.heading')
local code = require('inkmd.handlers.code')
local link = require('inkmd.handlers.link')
local list = require('inkmd.handlers.list')
local inline = require('inkmd.handlers.inline')
local misc = require('inkmd.handlers.misc')
local quote = require('inkmd.handlers.quote')
local tbl = require('inkmd.handlers.table')

local M = {}

local block_handlers = {
  -- Record leaf spans up front so inline marks find their block without a tree walk.
  leaf = function(ctx, node)
    local ls, le = ts.row_span(node)
    for row = ls, le - 1 do
      ctx.leaves[row] = ctx.leaves[row] or { ls, le }
    end
  end,
  heading = heading,
  code = code.render,
  bullet = list.bullet,
  ordered = list.ordered,
  quote = quote,
  rule = misc.rule,
  frontmatter = misc.frontmatter,
  html_block = misc.html_block,
  table = tbl,
}

local inline_handlers = {
  code_span = inline.code_span,
  delimiter = inline.delimiter,
  link = link.link,
  shortcut = link.shortcut,
  autolink = link.autolink,
  image = link.image,
  entity = link.entity,
  html_tag = link.html_tag,
  escape = inline.escape,
}

--- Rows to render: the union of every window's view plus a margin, the visible rows alone,
--- and the narrowest text width among those windows.
---@return integer? start, integer? stop, integer avail, integer? visible_start, integer? visible_stop
local function view(buf)
  local s, e, vs, ve, avail
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    local margin = math.max(20, vim.api.nvim_win_get_height(win))
    -- line('w0')/('w$') recompute the view; getwininfo() is only updated by a redraw.
    local top = vim.fn.line('w0', win) - 1
    local bot = vim.fn.line('w$', win)
    vs = vs and math.min(vs, top) or top
    ve = ve and math.max(ve, bot) or bot
    s = s and math.min(s, top - margin) or top - margin
    e = e and math.max(e, bot + margin) or bot + margin
    -- nvim_win_get_width is current; getwininfo().width only updates on redraw.
    local width = vim.api.nvim_win_get_width(win) - info.textoff
    avail = avail and math.min(avail, width) or width
  end
  if not s then
    return nil, nil, vim.o.columns
  end
  local count = vim.api.nvim_buf_line_count(buf)
  return math.max(s, 0), math.min(e, count), avail, vs, math.min(ve, count)
end

--- Rendering is paused while a nowrap window is scrolled sideways.
local function scrolled_sideways(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if not vim.wo[win].wrap and vim.fn.getwininfo(win)[1].leftcol > 0 then
      return true
    end
  end
  return false
end

--- Run the handlers over rows [s, e) of a parsed buffer and apply the marks.
local function emit(buf, st, parser, s, e, avail, tick)
  local cfg = config.options
  local ctx = marks.new(buf, avail)

  local block_query = ts.query('markdown')
  for _, tree in ipairs(parser:trees()) do
    for id, node in block_query:iter_captures(tree:root(), buf, s, e) do
      local handler = block_handlers[block_query.captures[id]]
      if handler then
        handler(ctx, node, cfg)
      end
    end
  end

  local inline_query = ts.query('markdown_inline')
  for _, tree in ipairs(ts.inline_trees(parser, s, e)) do
    local root = tree:root()
    local rs, _, re = root:range()
    for id, node in inline_query:iter_captures(root, buf, s, e) do
      local handler = inline_handlers[inline_query.captures[id]]
      if handler then
        -- Inline nodes live in an injected tree; their block comes from the row.
        ctx:block(ctx:leaf((node:range())))
        handler(ctx, node, cfg)
      end
    end
    for row = math.max(rs, s), math.min(re, e - 1) do
      ctx:block(ctx:leaf(row))
      inline.highlights(ctx, root, row)
    end
  end

  ctx:run_deferred()
  marks.apply(buf, ctx.marks)
  st.marks, st.tick, st.range, st.avail = ctx.marks, tick, { s, e }, avail
  st.raw = nil
  hybrid.update(buf)
end

---@param buf integer
---@param force? boolean re-render synchronously, even if the cached range covers the view
function M.render(buf, force)
  local st = state.get(buf)
  if not st or not st.enabled or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local s, e, avail, vs, ve = view(buf)
  if not s then
    return
  end
  if scrolled_sideways(buf) then
    M.clear(buf)
    return
  end
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  local cached = st.range and st.tick == tick and st.avail == avail and st.range[1] <= s and e <= st.range[2]
  if cached and not force then
    hybrid.update(buf)
    return
  end

  local parser = ts.parser(buf)
  if not parser then
    return
  end
  -- After an edit, parse only the visible rows: the highlighter has just parsed them, while
  -- every other range would redo injection bookkeeping for the whole document (~10 ms on
  -- 10k lines). Margin rows keep their edited, position-adjusted inline trees, and only the
  -- visible range counts as cached, so the next scroll parses the margin too.
  local edited = st.tick ~= nil and st.tick ~= tick
  local ps, pe = s, e
  if edited then
    ps, pe = vs, ve
  end
  local function done()
    emit(buf, st, parser, s, e, avail, tick)
    if edited then
      st.range = { vs, ve }
    end
  end
  if force then
    parser:parse({ ps, pe })
    done()
    return
  end
  -- Parse without blocking: Neovim yields every few ms and calls back when done (right
  -- away if the tree was already current, e.g. the highlighter parsed it on redraw).
  parser:parse({ ps, pe }, function(err)
    if err or not vim.api.nvim_buf_is_valid(buf) or state.get(buf) ~= st or not st.enabled then
      return
    end
    if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
      return M.render(buf)
    end
    done()
  end)
end

--- Remove all rendering from the buffer (it stays attached).
function M.clear(buf)
  local st = state.get(buf)
  vim.api.nvim_buf_clear_namespace(buf, marks.ns, 0, -1)
  if st then
    st.marks, st.tick, st.range, st.raw = {}, nil, nil, nil
  end
end

return M
