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
-- Commands by backend. merman-cli takes mmdc's arguments; mmdr has its own.
local function command(backend, opts)
  return backend == 'mmdc' and opts.cmd or opts[backend]
end

--- The backend to use: `opts.backend`, or with 'auto' the first one installed of merman
--- (a Rust port of Mermaid, output close to mmdc's), mmdc and mmdr (fastest, but its
--- layouts differ and it draws some invalid diagrams without an error).
---@return 'mmdc'|'merman'|'mmdr'
function M.backend(opts)
  if opts.backend ~= 'auto' then
    return opts.backend
  end
  for _, backend in ipairs({ 'merman', 'mmdc', 'mmdr' }) do
    if vim.fn.executable(command(backend, opts)) == 1 then
      return backend
    end
  end
  return 'mmdc'
end

function M.key(source, opts)
  return vim.fn.sha256(table.concat({
    'mermaid',
    M.backend(opts),
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
--- mmdr: SVG with a transparent background (its PNGs have a grey one and no scale option),
--- scaled to PNG by rsvg-convert, or its own PNG without it.
local function mmdr_argv(opts, input, dir)
  local argv = { opts.mmdr, '-i', input, '-t', M.theme(opts) }
  if not vim.tbl_contains(opts.args, '-c') then
    local config = vim.fs.joinpath(dir, 'config.json')
    local f = io.open(config, 'w')
    if f then
      f:write(vim.json.encode({ themeVariables = { background = opts.background } }))
      f:close()
      vim.list_extend(argv, { '-c', config })
    end
  end
  return vim.list_extend(argv, opts.args)
end

function M.job(source, key, opts)
  local backend = M.backend(opts)
  return function(done)
    local out = pipeline.cache_path(key)
    local dir = out .. '.d'
    vim.fn.mkdir(dir, 'p')
    local input = vim.fs.joinpath(dir, 'diagram.mmd')
    local f = io.open(input, 'w')
    if not f then
      return done({ status = 'error', message = 'cannot write ' .. input })
    end
    f:write(source)
    f:close()
    -- Called from process callbacks, where Vimscript functions are off limits.
    local finish = vim.schedule_wrap(function(result)
      vim.fn.delete(dir, 'rf')
      done(result)
    end)
    if backend ~= 'mmdr' then
      local argv = { command(backend, opts), '-q', '-i', input, '-o', '{out}', '-t', M.theme(opts), '-b', opts.background, '-s', tostring(opts.scale) }
      vim.list_extend(argv, opts.args)
      return pipeline.run(argv, out, opts.timeout, M.parse_error, finish)
    end
    local argv = mmdr_argv(opts, input, dir)
    if vim.fn.executable('rsvg-convert') == 0 then
      vim.list_extend(argv, { '-e', 'png', '-o', '{out}' })
      return pipeline.run(argv, out, opts.timeout, M.parse_error, finish)
    end
    if vim.fn.executable(opts.mmdr) == 0 then
      return finish({ status = 'error', message = opts.mmdr .. ' not found' })
    end
    local svg = vim.fs.joinpath(dir, 'diagram.svg')
    vim.list_extend(argv, { '-e', 'svg', '-o', svg })
    local ok, err = pcall(vim.system, argv, { text = true, timeout = opts.timeout }, function(res)
      if res.code ~= 0 or not vim.uv.fs_stat(svg) then
        return finish({ status = 'error', message = M.parse_error((res.stderr or '') .. '\n' .. (res.stdout or '')) })
      end
      pipeline.run({ 'rsvg-convert', '-z', tostring(opts.scale), '-o', '{out}', svg }, out, opts.timeout, function(output)
        return vim.trim(output) ~= '' and vim.trim(output) or 'rsvg-convert failed'
      end, finish)
    end)
    if not ok then
      finish({ status = 'error', message = tostring(err) })
    end
  end
end

return M
