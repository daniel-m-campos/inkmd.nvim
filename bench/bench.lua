-- Performance budget check on a generated 10k-line document.
--   nvim --headless --clean -l bench/bench.lua
-- Exits non-zero if any p95 exceeds 3x its budget (headroom for noisy machines).
-- Budgets cover time inkmd blocks the editor. Tree-sitter parsing that Neovim's own
-- highlighter does anyway on redraw is reported separately ("info" rows, no budget).

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
vim.o.columns = 100
vim.cmd('runtime plugin/inkmd.lua')

local inkmd = require('inkmd')
local hybrid = require('inkmd.hybrid')
local render = require('inkmd.render')
local state = require('inkmd.state')

local function document(n)
  local lines = {}
  local i = 0
  local function add(s)
    i = i + 1
    lines[i] = s
  end
  while i < n do
    add('## Section ' .. i)
    add('')
    add('Some text with `code`, *emphasis*, **strong** and a [link](https://example.com).')
    add('')
    add('- item one')
    add('  - nested item')
    add('- [ ] task')
    add('- [x] done')
    add('')
    add('> [!NOTE]')
    add('> A callout with a [link](https://github.com/x) and &amp;.')
    add('')
    add('| a | b |')
    add('|---|:-:|')
    add('| `x` | [y](https://example.com) |')
    add('')
    add('```lua')
    add('local x = ' .. i)
    add('print(x)')
    add('```')
    add('')
  end
  return lines
end

local function ms(t0)
  return (vim.uv.hrtime() - t0) / 1e6
end

local function stats(samples)
  table.sort(samples)
  local function pct(p)
    return samples[math.max(1, math.ceil(#samples * p))]
  end
  return pct(0.5), pct(0.95)
end

local lines = document(10000)
vim.cmd('enew')
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

local results, failed = {}, false
local function record(name, samples, budget)
  local p50, p95 = stats(samples)
  local status = 'info'
  if budget then
    status = p95 <= budget and 'ok' or (p95 <= 3 * budget and 'slow' or 'FAIL')
    failed = failed or status == 'FAIL'
  end
  results[#results + 1] = string.format(
    '%-16s p50 %7.3f ms   p95 %7.3f ms   %s',
    name,
    p50,
    p95,
    budget and string.format('budget %5.2f ms   %s', budget, status) or status
  )
end

-- Attach: FileType handling (ftplugin + inkmd) must return fast; the first render
-- parses asynchronously and lands a few event-loop turns later.
local attach, paint = {}, {}
for _ = 1, 6 do
  vim.cmd('enew!')
  buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  local t = vim.uv.hrtime()
  vim.bo[buf].filetype = 'markdown'
  attach[#attach + 1] = ms(t)
  vim.wait(5000, function()
    return state.get(buf).tick ~= nil
  end, 1)
  paint[#paint + 1] = ms(t)
end
-- The first attach also loads modules, the ftplugin and the parser (Neovim alone: ~12 ms).
record('attach (cold)', { table.remove(attach, 1) })
record('attach', attach, 25)
record('first paint', paint)

-- Render: a full re-render at positions spread over the document. Parsing is done up front
-- (the highlighter parses what becomes visible anyway) and reported separately.
local t_parse = vim.uv.hrtime()
vim.treesitter.get_parser(buf):parse(true)
record('nvim full parse', { ms(t_parse) })
local full = {}
for k = 1, 100 do
  vim.api.nvim_win_set_cursor(0, { math.floor(#lines * (k % 20 + 1) / 21), 0 })
  local t = vim.uv.hrtime()
  inkmd.render_now(buf)
  full[#full + 1] = ms(t)
end
record('render', full, 5)

-- Edit: the highlighter re-parses the visible range on the redraw after a keystroke,
-- then the debounced render runs on the current tree.
local edit, parse = {}, {}
local parser = vim.treesitter.get_parser(buf)
vim.api.nvim_win_set_cursor(0, { 5000, 0 })
-- Typing: append to paragraph lines near the cursor (inserting at column 0 would break
-- fences and restructure the whole document on every edit).
local text_rows = {}
for row = 4950, 5050 do
  if lines[row + 1]:match('^Some text') then
    text_rows[#text_rows + 1] = row
  end
end
for k = 1, 200 do
  local row = text_rows[k % #text_rows + 1]
  local col = #vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  vim.api.nvim_buf_set_text(buf, row, col, row, col, { 'x' })
  local t = vim.uv.hrtime()
  parser:parse({ 4950, 5050 })
  parse[#parse + 1] = ms(t)
  t = vim.uv.hrtime()
  render.render(buf)
  edit[#edit + 1] = ms(t)
  assert(state.get(buf).tick == vim.api.nvim_buf_get_changedtick(buf), 'render did not finish synchronously')
end
record('edit', edit, 5)
record('nvim parse', parse)

local move = {}
for k = 1, 1000 do
  vim.api.nvim_win_set_cursor(0, { 4980 + (k % 40), 0 })
  local t = vim.uv.hrtime()
  hybrid.update(buf)
  move[#move + 1] = ms(t)
end
record('hybrid move', move, 0.3)

io.stdout:write(table.concat(results, '\n'), '\n')
vim.cmd(failed and 'cquit 1' or 'qa!')
