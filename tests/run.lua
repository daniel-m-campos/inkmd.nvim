-- Minimal test runner: describe/it/eq, no dependencies.
--   nvim --headless --clean -l tests/run.lua [pattern]
-- Set UPDATE=1 to rewrite golden files.

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
vim.opt.rtp:prepend(root)
package.path = root .. '/tests/?.lua;' .. package.path
vim.o.columns = 80
vim.cmd('runtime plugin/inkmd.lua')

local filter = _G.arg[1]
local results = { passed = 0, failed = 0, failures = {} }
local current = {}

function _G.describe(name, fn)
  table.insert(current, name)
  fn()
  table.remove(current)
end

function _G.it(name, fn)
  local full = table.concat(current, ' > ') .. ' > ' .. name
  if filter and not full:find(filter, 1, true) then
    return
  end
  require('helpers').reset()
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    results.passed = results.passed + 1
    io.stdout:write('  ok    ', full, '\n')
  else
    results.failed = results.failed + 1
    table.insert(results.failures, full .. '\n' .. tostring(err))
    io.stdout:write('  FAIL  ', full, '\n')
  end
end

local specs = vim.fn.glob(root .. '/tests/*_spec.lua', false, true)
table.sort(specs)
for _, spec in ipairs(specs) do
  io.stdout:write(vim.fn.fnamemodify(spec, ':t'), '\n')
  dofile(spec)
end

for _, failure in ipairs(results.failures) do
  io.stdout:write('\n', failure, '\n')
end
io.stdout:write(string.format('\n%d passed, %d failed\n', results.passed, results.failed))
vim.cmd(results.failed > 0 and 'cquit 1' or 'qa!')
