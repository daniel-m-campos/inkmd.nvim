local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
M.ns = require('inkmd.marks').ns

--- Fresh editor state between tests: one window, no buffers, default options.
function M.reset()
  vim.cmd('silent! only!')
  vim.cmd('silent! %bwipeout!')
  vim.o.columns = 80
end

---@param a any
---@param b any
---@param msg? string
function M.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(string.format('%sexpected:\n%s\ngot:\n%s', msg and (msg .. '\n') or '', vim.inspect(b), vim.inspect(a)), 2)
  end
end

function M.truthy(v, msg)
  if not v then
    error(msg or 'expected a truthy value', 2)
  end
end

--- Open a fixture and render it synchronously.
---@param name string file in tests/fixtures
---@param cursor? {[1]: integer, [2]: integer} 1-based row, 0-based col
function M.open(name, cursor)
  vim.cmd('edit ' .. vim.fn.fnameescape(M.root .. '/tests/fixtures/' .. name))
  if cursor then
    vim.api.nvim_win_set_cursor(0, cursor)
  end
  require('inkmd').render_now(0)
  return vim.api.nvim_get_current_buf()
end

--- Open a scratch markdown buffer with `lines`.
function M.scratch(lines, cursor)
  vim.cmd('enew')
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.bo.filetype = 'markdown'
  if cursor then
    vim.api.nvim_win_set_cursor(0, cursor)
  end
  require('inkmd').render_now(0)
  return vim.api.nvim_get_current_buf()
end

--- Rendered screen rows 1..rows, trailing spaces removed.
function M.screen(rows, cols)
  -- Full repaint: a plain :redraw can leave stale rows in the headless grid.
  vim.cmd('redraw!')
  rows = rows or vim.o.lines - 2
  cols = cols or vim.o.columns
  local out = {}
  for r = 1, rows do
    local s = {}
    for c = 1, cols do
      s[#s + 1] = vim.fn.screenstring(r, c)
    end
    out[#out + 1] = (table.concat(s):gsub('%s+$', ''))
  end
  while #out > 0 and (out[#out] == '' or out[#out] == '~') do
    out[#out] = nil
  end
  return out
end

--- Compare `lines` with tests/golden/<name>.txt; UPDATE=1 rewrites it.
function M.golden(name, lines)
  local path = M.root .. '/tests/golden/' .. name .. '.txt'
  if os.getenv('UPDATE') == '1' or vim.fn.filereadable(path) == 0 then
    vim.fn.writefile(lines, path)
    return
  end
  local expected = vim.fn.readfile(path)
  if not vim.deep_equal(lines, expected) then
    local diff = vim.text.diff(table.concat(expected, '\n') .. '\n', table.concat(lines, '\n') .. '\n')
    error('golden mismatch for ' .. name .. ' (UPDATE=1 to accept):\n' .. diff, 2)
  end
end

--- Extmarks in our namespace, with details.
function M.marks(buf)
  return vim.api.nvim_buf_get_extmarks(buf or 0, M.ns, 0, -1, { details = true })
end

--- Marks touching `row` (0-based) that use highlight group `group`.
function M.marks_with_hl(buf, row, group)
  local found = {}
  for _, m in ipairs(M.marks(buf)) do
    local d = m[4]
    if m[2] == row and (d.hl_group == group or d.line_hl_group == group) then
      found[#found + 1] = m
    end
  end
  return found
end

return M
