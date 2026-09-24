-- Treesitter access: the shared markdown parser, our capture queries, and removal of the
-- bundled highlight queries' conceal directives (they conceal per line, which would fight
-- the per-element hybrid view).
local M = {}

local stripped = false

--- Remove `(#set! conceal ...)` and `(#set! conceal_lines ...)` from the bundled markdown
--- highlight queries, keeping all of their colours. Affects the whole session.
function M.strip_bundled_conceal()
  if stripped then
    return
  end
  stripped = true
  for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
    local parts = {}
    for _, file in ipairs(vim.treesitter.query.get_files(lang, 'highlights')) do
      parts[#parts + 1] = table.concat(vim.fn.readfile(file), '\n')
    end
    -- Lazy match up to '")' so escaped quotes such as conceal "\"" are handled.
    local src = table.concat(parts, '\n')
      :gsub('%(#set!%s+conceal_lines%s+".-"%)', '')
      :gsub('%(#set!%s+conceal%s+".-"%)', '')
    vim.treesitter.query.set(lang, 'highlights', src)
  end
  -- Highlighters started before this keep the old query; restart them.
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.treesitter.highlighter.active[buf] and vim.bo[buf].filetype == 'markdown' then
      vim.treesitter.stop(buf)
      vim.treesitter.start(buf, 'markdown')
    end
  end
end

local block_query_src = [[
(atx_heading) @heading
(setext_heading) @heading
(fenced_code_block) @code
(list_marker_minus) @bullet
(list_marker_plus) @bullet
(list_marker_star) @bullet
(list_marker_dot) @ordered
(list_marker_parenthesis) @ordered
(block_quote) @quote
(thematic_break) @rule
(minus_metadata) @frontmatter
(plus_metadata) @frontmatter
(html_block) @html_block
(pipe_table) @table
[
  (paragraph) (atx_heading) (setext_heading) (fenced_code_block) (indented_code_block)
  (pipe_table) (thematic_break) (html_block) (link_reference_definition)
] @leaf
]]

local inline_query_src = [[
(code_span) @code_span
(code_span_delimiter) @delimiter
(emphasis_delimiter) @delimiter
(inline_link) @link
(full_reference_link) @link
(collapsed_reference_link) @link
(shortcut_link) @shortcut
(uri_autolink) @autolink
(email_autolink) @autolink
(image) @image
(entity_reference) @entity
(numeric_character_reference) @entity
(html_tag) @html_tag
(backslash_escape) @escape
]]

local queries = {}

---@param lang 'markdown'|'markdown_inline'
---@return vim.treesitter.Query
function M.query(lang)
  if not queries[lang] then
    queries[lang] = vim.treesitter.query.parse(lang, lang == 'markdown' and block_query_src or inline_query_src)
  end
  return queries[lang]
end

---@param buf integer
---@return vim.treesitter.LanguageTree?
function M.parser(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, 'markdown')
  return ok and parser or nil
end

--- Injected markdown_inline trees overlapping rows [s, e]. Regions are in document order,
--- so a binary search avoids touching (and allocating nodes for) thousands of trees.
---@param parser vim.treesitter.LanguageTree
---@return TSTree[]
function M.inline_trees(parser, s, e)
  local child = parser:children().markdown_inline
  if not child then
    return {}
  end
  local regions, trees = child:included_regions(), child:trees()
  local n = #regions
  -- Range6 = { start_row, start_col, start_byte, end_row, end_col, end_byte }
  local lo, hi = 1, n + 1
  while lo < hi do
    local mid = math.floor((lo + hi) / 2)
    local region = regions[mid]
    if region[#region][4] < s then
      lo = mid + 1
    else
      hi = mid
    end
  end
  local out = {}
  for i = lo, n do
    local region = regions[i]
    if region[1][1] > e then
      break
    end
    if trees[i] then
      out[#out + 1] = trees[i]
    end
  end
  return out
end

--- Block node types that are rendered or shown raw as a unit.
M.leaf_blocks = {
  atx_heading = true,
  setext_heading = true,
  fenced_code_block = true,
  indented_code_block = true,
  pipe_table = true,
  paragraph = true,
  thematic_break = true,
  html_block = true,
  minus_metadata = true,
  plus_metadata = true,
  link_reference_definition = true,
}

--- Rows [start, end) a node really occupies. Nodes ending at column 0 don't include that
--- row, and a leaf's trailing `block_continuation` (the next line's indent) is ignored.
---@param node TSNode
---@return integer, integer
function M.row_span(node)
  local sr, _, er, ec = node:range()
  if M.leaf_blocks[node:type()] then
    local last
    for child in node:iter_children() do
      if child:named() and child:type() ~= 'block_continuation' then
        last = child
      end
    end
    if last then
      _, _, er, ec = last:range()
    end
  end
  if ec == 0 and er > sr then
    er = er - 1
  end
  return sr, er + 1
end

--- Rows [start, end) of the leaf block covering `row` and the block's node, or nil (blank
--- lines, containers only).
---@param buf integer
---@param row integer 0-based
---@return integer?, integer?
function M.leaf_span(buf, row)
  local parser = M.parser(buf)
  local tree = parser and parser:trees()[1]
  if not tree then
    return nil
  end
  -- Depth-first over children covering the row: a list item row is covered by both its
  -- marker (a dead end) and its paragraph (the leaf).
  local function search(node)
    for child in node:iter_children() do
      local cs, _, ce = child:range()
      if cs > row then
        break
      end
      -- range() bounds the real span, so row_span is only needed for a possible match.
      if child:named() and ce >= row then
        local s, e = M.row_span(child)
        if s <= row and row < e then
          if M.leaf_blocks[child:type()] then
            return s, e, child
          end
          local fs, fe, fnode = search(child)
          if fs then
            return fs, fe, fnode
          end
        end
      end
    end
  end
  -- Start from the enclosing leaf or section instead of scanning the whole document.
  local root = tree:root()
  local node = root:named_descendant_for_range(row, 0, row, 0)
  while node do
    local t = node:type()
    if M.leaf_blocks[t] then
      local s, e = M.row_span(node)
      if s <= row and row < e then
        return s, e, node
      end
    elseif t == 'section' or t == 'document' then
      break
    end
    node = node:parent()
  end
  return search(node or root)
end

return M
