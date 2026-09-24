-- Headless checks for the core renderer's riskiest assumptions.
--   nvim --headless --clean -l spike/core_spike.lua
-- Prints PASS/FAIL per check; results are recorded in DESIGN.md.

vim.o.columns, vim.o.lines = 60, 20
local results = {}

local function check(name, ok, detail)
  results[#results + 1] = string.format('%s  %s%s', ok and 'PASS' or 'FAIL', name, detail and ('  (' .. detail .. ')') or '')
end

local function screen(rows, cols)
  vim.cmd('redraw')
  local out = {}
  for r = 1, rows do
    local s = {}
    for c = 1, cols do
      s[#s + 1] = vim.fn.screenstring(r, c)
    end
    out[#out + 1] = (table.concat(s):gsub('%s+$', ''))
  end
  return out
end

local function fresh(lines)
  vim.cmd('enew!')
  vim.bo.buftype = 'nofile'
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  return vim.api.nvim_get_current_buf()
end

local ns = vim.api.nvim_create_namespace('core_spike')

-- 1. A virt_lines_above block taller than the window scrolls one row at a time. ------
do
  local lines = {}
  for i = 1, 40 do
    lines[i] = 'line ' .. i
  end
  local buf = fresh(lines)
  local block = {}
  for i = 1, 30 do
    block[i] = { { 'block ' .. i, 'Comment' } }
  end
  -- Hide rows 5..9 (0-based 4..8) and hang the block above row 10 (0-based 9).
  vim.api.nvim_buf_set_extmark(buf, ns, 4, 0, { end_row = 8, conceal_lines = '' })
  vim.api.nvim_buf_set_extmark(buf, ns, 9, 0, { virt_lines = block, virt_lines_above = true })
  vim.wo.conceallevel = 2
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.cmd('normal! gg')
  -- Scroll until the anchor is the top line, then step through its filler with <C-e>.
  local tops, fills = {}, {}
  for _ = 1, 40 do
    vim.cmd('execute "normal! \\<C-e>"')
    vim.cmd('redraw')
    local v = vim.fn.winsaveview()
    tops[#tops + 1] = v.topline
    fills[#fills + 1] = v.topfill
  end
  local seen_partial = false
  for i, f in ipairs(fills) do
    if tops[i] == 10 and f > 0 and f < 30 then
      seen_partial = true
    end
  end
  local s = screen(3, 30)
  check('tall virt_lines_above scrolls through topfill', seen_partial, 'fills=' .. table.concat(fills, ',', 1, math.min(#fills, 16)) .. ' first row now: ' .. s[1])
end

-- 2. Inline virt_text plus breakindent list:-1 gives a hanging indent. -------------------
do
  local buf = fresh({ '- ' .. string.rep('word ', 25), 'cursor here' })
  -- Keep the cursor off the list row: concealcursor='' shows the cursor row raw.
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  vim.wo.wrap = true
  vim.wo.breakindent = true
  vim.wo.breakindentopt = 'list:-1'
  vim.bo.formatlistpat = [[^\s*[-*+]\s\+]]
  vim.wo.conceallevel = 3
  -- Replace "-" with an inline bullet, like the list handler will.
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = 1, conceal = '' })
  vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { virt_text = { { '●', 'Special' } }, virt_text_pos = 'inline' })
  local s = screen(3, 60)
  local second = s[2] or ''
  local indent = #second:match('^%s*')
  local bullet_ok = vim.startswith(s[1], '● word')
  check('inline bullet replaces the concealed marker', bullet_ok, 'row1=' .. s[1]:sub(1, 20))
  check('breakindent list:-1 hangs wrapped list text under the first word', indent == 2, 'row2 indent=' .. indent)
end

-- 3. Stripping conceal directives from the bundled markdown queries. -------------------
do
  local stripped = {}
  for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
    local files = vim.treesitter.query.get_files(lang, 'highlights')
    local text = {}
    for _, file in ipairs(files) do
      text[#text + 1] = table.concat(vim.fn.readfile(file), '\n')
    end
    local src = table.concat(text, '\n')
    local before = select(2, src:gsub('conceal', ''))
    -- Lazy match up to '")' so escaped quotes such as conceal "\"" are handled.
    src = src:gsub('%(#set!%s+conceal_lines%s+".-"%)', ''):gsub('%(#set!%s+conceal%s+".-"%)', '')
    vim.treesitter.query.set(lang, 'highlights', src)
    local query = vim.treesitter.query.get(lang, 'highlights')
    local leftover = 0
    for _, pattern in pairs(query.info.patterns) do
      for _, directive in ipairs(pattern) do
        if directive[2] == 'conceal' or directive[2] == 'conceal_lines' then
          leftover = leftover + 1
        end
      end
    end
    stripped[#stripped + 1] = string.format('%s: %d mentions before, %d conceal directives left', lang, before, leftover)
    check('strip conceal from ' .. lang .. ' highlights', leftover == 0 and before > 0, stripped[#stripped])
  end
  -- Highlighting still works after the swap.
  local buf = fresh({ '# Title', '', 'some **bold** and `code`', '', '```lua', 'x = 1', '```' })
  vim.bo[buf].filetype = 'markdown'
  vim.treesitter.start(buf, 'markdown')
  vim.wo.conceallevel = 2
  local s = screen(7, 30)
  check('fences and markers stay visible after stripping', s[5] == '```lua' and s[3]:find('**', 1, true) ~= nil, 'row3=' .. s[3] .. ' row5=' .. s[5])
  local caps = vim.treesitter.get_captures_at_pos(buf, 0, 2)
  local names = vim.tbl_map(function(c)
    return c.capture
  end, caps)
  check('heading still highlighted', vim.tbl_contains(names, 'markup.heading.1'), table.concat(names, ','))
end

-- 4. virt_lines on a concealed row are not drawn (anchor rule). ------------------------
do
  local buf = fresh({ 'a', 'b', 'c' })
  vim.wo.conceallevel = 2
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { conceal_lines = '' })
  vim.api.nvim_buf_set_extmark(buf, ns, 1, 0, { virt_lines = { { { 'VL', 'Comment' } } } })
  local s = screen(3, 5)
  check('virt_lines on a concealed row are dropped', s[2] == 'c' and s[1] == 'a', table.concat(s, '|'))
end

io.stdout:write(table.concat(results, '\n'), '\n')
vim.cmd('qa!')
