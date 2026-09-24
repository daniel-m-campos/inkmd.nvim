-- The render pipeline: visible range -> parse -> handlers -> marks -> apply -> hybrid.
local config = require('inkmd.config')
local hybrid = require('inkmd.hybrid')
local marks = require('inkmd.marks')
local state = require('inkmd.state')
local ts = require('inkmd.ts')

local heading = require('inkmd.handlers.heading')
local code = require('inkmd.handlers.code')
local list = require('inkmd.handlers.list')
local inline = require('inkmd.handlers.inline')

local M = {}

local block_handlers = {
  heading = heading,
  code = code,
  bullet = list.bullet,
  ordered = list.ordered,
}

local inline_handlers = {
  code_span = inline.code_span,
  delimiter = inline.delimiter,
}

--- Rows to render: the union of every window's view plus a margin, and the narrowest
--- text width among those windows.
---@return integer? start, integer? stop, integer avail
local function view(buf)
  local s, e, avail
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local info = vim.fn.getwininfo(win)[1]
    local margin = math.max(20, info.height)
    -- line('w0')/('w$') recompute the view; getwininfo() is only updated by a redraw.
    local top = vim.fn.line('w0', win) - 1 - margin
    local bot = vim.fn.line('w$', win) + margin
    s = s and math.min(s, top) or top
    e = e and math.max(e, bot) or bot
    local width = info.width - info.textoff
    avail = avail and math.min(avail, width) or width
  end
  if not s then
    return nil, nil, vim.o.columns
  end
  return math.max(s, 0), math.min(e, vim.api.nvim_buf_line_count(buf)), avail
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

--- Leaf block rows for a row of inline content, so inline marks hide with their block in
--- hybrid mode. Inline nodes live in an injected tree, so this goes through the block tree.
---@param cache table<integer, integer[]>
local function inline_span(buf, row, cache)
  local span = cache[row]
  if not span then
    local s, e = ts.leaf_span(buf, row)
    span = s and { s, e } or { row, row + 1 }
    cache[row] = span
  end
  return span[1], span[2]
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

  local inline_tree = parser:children().markdown_inline
  if inline_tree then
    local inline_query = ts.query('markdown_inline')
    local spans = {}
    for _, tree in ipairs(inline_tree:trees()) do
      local root = tree:root()
      local rs, _, re = root:range()
      if rs <= e and re >= s then
        for id, node in inline_query:iter_captures(root, buf, s, e) do
          local handler = inline_handlers[inline_query.captures[id]]
          if handler then
            ctx:block(inline_span(buf, (node:range()), spans))
            handler(ctx, node, cfg)
          end
        end
      end
    end
  end

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
  local s, e, avail = view(buf)
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
  if force then
    parser:parse({ s, e })
    emit(buf, st, parser, s, e, avail, tick)
    return
  end
  -- Parse without blocking: Neovim yields every few ms and calls back when done (right
  -- away if the tree was already current, e.g. the highlighter parsed it on redraw).
  parser:parse({ s, e }, function(err)
    if err or not vim.api.nvim_buf_is_valid(buf) or state.get(buf) ~= st or not st.enabled then
      return
    end
    if vim.api.nvim_buf_get_changedtick(buf) ~= tick then
      return M.render(buf)
    end
    emit(buf, st, parser, s, e, avail, tick)
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
