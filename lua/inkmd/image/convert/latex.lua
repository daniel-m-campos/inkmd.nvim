-- Display math via latex + dvipng: the formula is typeset in the buffer text's colour on a
-- transparent background, at a resolution matching the terminal's cell height.
local pipeline = require('inkmd.image.pipeline')

local M = {}

--- Foreground colour for formulas, as RRGGBB.
function M.color()
  local fg = vim.api.nvim_get_hl(0, { name = 'Normal', link = false }).fg
  if fg then
    return string.format('%06X', fg)
  end
  return vim.o.background == 'dark' and 'DDDDDD' or '222222'
end

--- dvipng resolution so 10pt text is about as tall as the buffer text (a cell is ~1.2 em).
---@param cell_height number pixels
---@param scale number
function M.dpi(cell_height, scale)
  return math.max(math.floor(cell_height / 1.2 * 7.2 * scale + 0.5), 50)
end

function M.key(source, opts, color, dpi, backend)
  return vim.fn.sha256(table.concat({ 'math', backend or 'latex', source, opts.preamble, color, tostring(dpi) }, '\0'))
end

--- The message from latex's output: the "! ..." line and the "l.N ..." line after it.
---@param output string
function M.parse_error(output)
  local lines = {}
  local capturing = false
  for line in output:gmatch('[^\n]+') do
    if line:match('^!') then
      capturing = true
      lines[#lines + 1] = line
    elseif capturing and line:match('^l%.%d+') then
      lines[#lines + 1] = line
      break
    end
  end
  return #lines > 0 and table.concat(lines, '\n') or 'latex failed'
end

local function document(source, opts, color)
  return table.concat({
    '\\documentclass[preview,border=1pt]{standalone}',
    opts.preamble,
    '\\usepackage{xcolor}',
    '\\begin{document}',
    '\\color[HTML]{' .. color .. '}',
    '$\\displaystyle ' .. source .. '$',
    '\\end{document}',
    '',
  }, '\n')
end

--- Job typesetting `source` to the cache path of `key`.
function M.job(source, key, opts, color, dpi)
  return function(done)
    if vim.fn.executable(opts.latex) == 0 then
      return done({ status = 'error', message = opts.latex .. ' not found' })
    end
    local out = pipeline.cache_path(key)
    local dir = out .. '.d'
    vim.fn.mkdir(dir, 'p')
    local tex = vim.fs.joinpath(dir, 'math.tex')
    local f = io.open(tex, 'w')
    if not f then
      return done({ status = 'error', message = 'cannot write ' .. tex })
    end
    f:write(document(source, opts, color))
    f:close()
    -- Called from process callbacks, where Vimscript functions are off limits.
    local finish = vim.schedule_wrap(function(result)
      vim.fn.delete(dir, 'rf')
      done(result)
    end)
    local argv = { opts.latex, '-interaction=nonstopmode', '-halt-on-error', '-output-directory=' .. dir, tex }
    local ok, err = pcall(vim.system, argv, { text = true, timeout = opts.timeout, cwd = dir }, vim.schedule_wrap(function(res)
      local dvi = vim.fs.joinpath(dir, 'math.dvi')
      if res.code ~= 0 or not vim.uv.fs_stat(dvi) then
        return finish({ status = 'error', message = M.parse_error((res.stdout or '') .. '\n' .. (res.stderr or '')) })
      end
      pipeline.run(
        { opts.dvipng, '-q', '-D', tostring(dpi), '-T', 'tight', '-bg', 'Transparent', '-o', '{out}', dvi },
        out,
        opts.timeout,
        function(output)
          return vim.trim(output) ~= '' and vim.trim(output) or 'dvipng failed'
        end,
        finish
      )
    end))
    if not ok then
      finish({ status = 'error', message = tostring(err) })
    end
  end
end

return M
