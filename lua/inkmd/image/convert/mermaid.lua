-- Mermaid diagrams via mmdc (@mermaid-js/mermaid-cli). Rendered once at `scale` and let the
-- terminal scale it, so the cache key doesn't depend on the window width.
local pipeline = require('inkmd.image.pipeline')

local M = {}

---@param opts table config.image.mermaid
function M.theme(opts)
  return opts.theme or (vim.o.background == 'dark' and 'dark' or 'default')
end

---@param source string
---@param opts table config.image.mermaid
function M.key(source, opts)
  return vim.fn.sha256(table.concat({
    'mermaid',
    source,
    M.theme(opts),
    opts.background,
    tostring(opts.scale),
    table.concat(opts.args, ' '),
  }, '\0'))
end

--- The error message part of mmdc's output: from "Error:" up to the stack trace.
---@param output string
function M.parse_error(output)
  output = output:gsub('\27%[[%d;]*m', '')
  local lines = {}
  local started = false
  for line in output:gmatch('[^\n]+') do
    if line:match('^%s*at ') or line:match('^Parser%.') or line:match('^%w+%.parseError') then
      break
    end
    started = started or line:match('Error') ~= nil
    if started and vim.trim(line) ~= '' then
      lines[#lines + 1] = line
    end
  end
  if #lines == 0 then
    return vim.trim(output) ~= '' and vim.trim(output) or 'mmdc failed'
  end
  return table.concat(lines, '\n')
end

--- Job that renders `source` to the cache path of `key`.
---@param source string
---@param key string
---@param opts table config.image.mermaid
function M.job(source, key, opts)
  return function(done)
    local out = pipeline.cache_path(key)
    local input = out .. '.mmd'
    local f = io.open(input, 'w')
    if not f then
      return done({ status = 'error', message = 'cannot write ' .. input })
    end
    f:write(source)
    f:close()
    local argv = { opts.cmd, '-q', '-i', input, '-o', '{out}', '-t', M.theme(opts), '-b', opts.background, '-s', tostring(opts.scale) }
    vim.list_extend(argv, opts.args)
    pipeline.run(argv, out, opts.timeout, M.parse_error, function(result)
      os.remove(input)
      done(result)
    end)
  end
end

return M
