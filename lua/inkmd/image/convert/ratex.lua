-- Display math with RaTeX (https://github.com/erweixin/RaTeX), a Rust port of KaTeX: one
-- process per formula, about 5 ms against about 250 ms for latex + dvipng. It knows
-- KaTeX's syntax, not arbitrary LaTeX packages; `fallback` takes over what it rejects.
local pipeline = require('inkmd.image.pipeline')
local png = require('inkmd.image.png')

local M = {}

--- 'ratex' or 'latex': `opts.backend`, or with 'auto' RaTeX when it is installed.
function M.backend(opts)
  if opts.backend ~= 'auto' then
    return opts.backend
  end
  return vim.fn.executable(opts.ratex) == 1 and 'ratex' or 'latex'
end

--- RaTeX's font size in pixels for the resolution latex would use: 10 pt at `dpi`.
function M.font_size(dpi)
  return string.format('%.1f', 10 * dpi / 72.27)
end

--- The message of RaTeX's "ERR  1 <formula> — Parse error: ..." line.
function M.parse_error(output)
  for line in output:gmatch('[^\n]+') do
    local message = line:match('^ERR%s+%d+%s.-—%s*(.+)$')
    if message then
      return message
    end
  end
  return vim.trim(output) ~= '' and vim.trim(output) or 'ratex failed'
end

---@param fallback? fun(done: fun(result: table)) job to run when RaTeX can't typeset the formula
function M.job(source, key, opts, color, dpi, fallback)
  return function(done)
    local out = pipeline.cache_path(key)
    local dir = out .. '.d'
    vim.fn.mkdir(dir, 'p')
    local input = vim.fs.joinpath(dir, 'math.txt')
    local f = io.open(input, 'w')
    if not f then
      return done({ status = 'error', message = 'cannot write ' .. input })
    end
    -- One formula per line: RaTeX reads line by line.
    f:write((source:gsub('%s+', ' ')), '\n')
    f:close()
    local finish = vim.schedule_wrap(function(result)
      vim.fn.delete(dir, 'rf')
      if result.status == 'error' and fallback then
        return fallback(done)
      end
      done(result)
    end)
    local argv = {
      opts.ratex,
      '--input',
      input,
      '--output-dir',
      dir,
      '--font-size',
      M.font_size(dpi),
      '--color',
      '#' .. color,
      '--background-color',
      'transparent',
    }
    local ok, err = pcall(vim.system, argv, { text = true, timeout = opts.timeout }, function(res)
      local file = vim.fs.joinpath(dir, '0001.png')
      if res.code == 0 and png.size(file) then
        os.rename(file, out)
        return finish(pipeline.from_png(out))
      end
      finish({ status = 'error', message = M.parse_error((res.stdout or '') .. '\n' .. (res.stderr or '')) })
    end)
    if not ok then
      finish({ status = 'error', message = tostring(err) })
    end
  end
end

return M
