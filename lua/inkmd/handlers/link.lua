-- Links, images, autolinks, wikilinks, footnotes, entities and inline HTML comments.
local hooks = require('inkmd.hooks')

local M = {}

local superscripts = {
  ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴', ['5'] = '⁵', ['6'] = '⁶',
  ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹', a = 'ᵃ', b = 'ᵇ', c = 'ᶜ', d = 'ᵈ', e = 'ᵉ', f = 'ᶠ',
  g = 'ᵍ', h = 'ʰ', i = 'ⁱ', j = 'ʲ', k = 'ᵏ', l = 'ˡ', m = 'ᵐ', n = 'ⁿ', o = 'ᵒ', p = 'ᵖ',
  r = 'ʳ', s = 'ˢ', t = 'ᵗ', u = 'ᵘ', v = 'ᵛ', w = 'ʷ', x = 'ˣ', y = 'ʸ', z = 'ᶻ', ['-'] = '⁻',
}

local entities = {
  amp = '&', lt = '<', gt = '>', quot = '"', apos = "'", nbsp = ' ', copy = '©', reg = '®',
  trade = '™', hellip = '…', mdash = '—', ndash = '–', lsquo = '‘', rsquo = '’', ldquo = '“',
  rdquo = '”', laquo = '«', raquo = '»', larr = '←', rarr = '→', uarr = '↑', darr = '↓',
  harr = '↔', times = '×', divide = '÷', plusmn = '±', deg = '°', middot = '·', bull = '•',
  sect = '§', para = '¶', euro = '€', pound = '£', yen = '¥', cent = '¢', check = '✓',
  ne = '≠', le = '≤', ge = '≥', infin = '∞', micro = 'µ', frac12 = '½', frac14 = '¼',
}

local def_query

--- Destinations of reference definitions ([label]: url), by lower-case label.
---@param ctx inkmd.Ctx
local function definitions(ctx)
  if ctx.defs then
    return ctx.defs
  end
  ctx.defs = {}
  local ok, parser = pcall(vim.treesitter.get_parser, ctx.buf, 'markdown')
  local tree = ok and parser:trees()[1]
  if not tree then
    return ctx.defs
  end
  def_query = def_query
    or vim.treesitter.query.parse('markdown', '(link_reference_definition (link_label) @label (link_destination) @dest)')
  local label
  for id, node in def_query:iter_captures(tree:root(), ctx.buf) do
    local text = vim.treesitter.get_node_text(node, ctx.buf)
    if def_query.captures[id] == 'label' then
      label = text:sub(2, -2):lower()
    elseif label then
      ctx.defs[label] = text
      label = nil
    end
  end
  return ctx.defs
end

---@param dest? string
---@param cfg inkmd.Config
local function icon_for(dest, cfg)
  local icons = cfg.link.icons
  if not dest then
    return icons.link
  end
  for _, d in ipairs(cfg.link.destinations) do
    if dest:find(d.pattern) then
      return d.icon
    end
  end
  if dest:match('^mailto:') then
    return icons.email
  elseif dest:match('^%a[%w+.-]*://') then
    return icons.web
  elseif dest:match('^#') then
    return icons.link
  end
  return icons.file
end

---@param node TSNode
---@param type string
local function child(node, type)
  for c in node:iter_children() do
    if c:type() == type then
      return c
    end
  end
end

--- Show only `text` of a link node: hide what comes before and after it, add an icon.
---@param ctx inkmd.Ctx
---@param node TSNode the whole link
---@param text TSNode the part that stays visible
local function show_text(ctx, node, text, icon, group, url)
  local sr, sc, er, ec = node:range()
  local tsr, tsc, ter, tec = text:range()
  if tsr ~= sr or ter ~= er then
    return
  end
  ctx:conceal(sr, sc, tsc)
  ctx:inline(sr, sc, { { icon, 'InkmdLinkIcon' } })
  ctx:hl(tsr, tsc, tec, group, false, url)
  ctx:conceal(er, tec, ec)
end

---@param ctx inkmd.Ctx
---@param node TSNode inline_link | full_reference_link | collapsed_reference_link
---@param cfg inkmd.Config
function M.link(ctx, node, cfg)
  local text = child(node, 'link_text')
  if not text then
    return
  end
  local dest_node = child(node, 'link_destination')
  local dest
  if dest_node then
    dest = vim.treesitter.get_node_text(dest_node, ctx.buf)
  else
    local label = child(node, 'link_label') or text
    local name = vim.treesitter.get_node_text(label, ctx.buf)
    if label ~= text then
      name = name:sub(2, -2)
    end
    dest = definitions(ctx)[(name == '' and vim.treesitter.get_node_text(text, ctx.buf) or name):lower()]
  end
  local url = dest and dest:match('^%a[%w+.-]*:') and dest or nil
  show_text(ctx, node, text, icon_for(dest, cfg), 'InkmdLink', url)
end

--- `[label]`: a wikilink when wrapped in another pair of brackets, a footnote reference
--- when the label starts with ^, a callout type (left to the quote handler) when it starts
--- with !, and otherwise a link only if a matching reference definition exists.
---@param ctx inkmd.Ctx
---@param node TSNode shortcut_link
---@param cfg inkmd.Config
function M.shortcut(ctx, node, cfg)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local line = ctx:line(sr)
  local label = line:sub(sc + 2, ec - 1)
  if label:sub(1, 1) == '!' then
    return
  end
  if line:sub(sc, sc) == '[' and line:sub(ec + 1, ec + 1) == ']' then
    local target = label:match('^([^|]*)') or label
    local alias = label:match('|(.*)$')
    ctx:conceal(sr, sc - 1, sc + 1)
    ctx:inline(sr, sc - 1, { { cfg.link.icons.wiki, 'InkmdLinkIcon' } })
    if alias then
      -- [[target|alias]] shows only the alias.
      ctx:conceal(sr, sc + 1, sc + 2 + #target)
    end
    ctx:hl(sr, sc + 1, ec - 1, 'InkmdLink')
    ctx:conceal(sr, ec - 1, ec + 1)
    return
  end
  if label:sub(1, 1) == '^' then
    ctx:hl(sr, sc, ec, 'InkmdFootnote')
    if cfg.link.footnote_superscript then
      local sup = {}
      for ch in label:sub(2):lower():gmatch('.') do
        sup[#sup + 1] = superscripts[ch]
      end
      if #sup == #label - 1 then
        ctx:conceal(sr, sc, ec)
        ctx:inline(sr, sc, { { table.concat(sup), 'InkmdFootnote' } })
      end
    end
    return
  end
  local dest = definitions(ctx)[label:lower()]
  if dest then
    local text = child(node, 'link_text')
    if text then
      show_text(ctx, node, text, icon_for(dest, cfg), 'InkmdLink', dest:match('^%a[%w+.-]*:') and dest or nil)
    end
  end
end

---@param ctx inkmd.Ctx
---@param node TSNode uri_autolink | email_autolink
---@param cfg inkmd.Config
function M.autolink(ctx, node, cfg)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local target = ctx:line(sr):sub(sc + 2, ec - 1)
  local email = node:type() == 'email_autolink'
  ctx:conceal(sr, sc, sc + 1)
  ctx:inline(sr, sc, { { email and cfg.link.icons.email or icon_for(target, cfg), 'InkmdLinkIcon' } })
  ctx:hl(sr, sc + 1, ec - 1, 'InkmdLink', false, email and ('mailto:' .. target) or target)
  ctx:conceal(sr, ec - 1, ec)
end

---@param ctx inkmd.Ctx
---@param node TSNode image
---@param cfg inkmd.Config
function M.image(ctx, node, cfg)
  local sr, sc, er, ec = node:range()
  local desc = child(node, 'image_description')
  local dest_node = child(node, 'link_destination')
  local src = dest_node and vim.treesitter.get_node_text(dest_node, ctx.buf)
  local alt = desc and vim.treesitter.get_node_text(desc, ctx.buf) or ''

  if src then
    local span = ctx.span
    local indent = #ctx:line(span[1]):match('^%s*')
    local claim = hooks.claim({ kind = 'image', buf = ctx.buf, src = src, text = alt, s = span[1], e = span[2], col = indent }, ctx)
    if claim then
      hooks.place(ctx, claim, span[1], span[2])
    end
  end

  if desc then
    show_text(ctx, node, desc, cfg.link.icons.image, 'InkmdLink')
  elseif src and sr == er then
    -- No alt text: show the file name.
    ctx:conceal(sr, sc, ec)
    ctx:inline(sr, sc, {
      { cfg.link.icons.image, 'InkmdLinkIcon' },
      { vim.fn.fnamemodify(src, ':t'), 'InkmdLink' },
    })
  end
end

---@param ctx inkmd.Ctx
---@param node TSNode entity_reference | numeric_character_reference
function M.entity(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr ~= er then
    return
  end
  local text = ctx:line(sr):sub(sc + 1, ec)
  local char
  local num = text:match('^&#[xX](%x+);$')
  if num then
    char = vim.fn.nr2char(tonumber(num, 16))
  else
    num = text:match('^&#(%d+);$')
    char = num and vim.fn.nr2char(tonumber(num)) or entities[text:match('^&(%w+);$') or '']
  end
  if char and char ~= '' then
    ctx:conceal(sr, sc, ec)
    ctx:inline(sr, sc, { { char } })
  end
end

--- Hide single-line inline HTML comments.
---@param ctx inkmd.Ctx
---@param node TSNode html_tag
function M.html_tag(ctx, node)
  local sr, sc, er, ec = node:range()
  if sr == er and ctx:line(sr):sub(sc + 1, sc + 4) == '<!--' then
    ctx:conceal(sr, sc, ec)
  end
end

return M
