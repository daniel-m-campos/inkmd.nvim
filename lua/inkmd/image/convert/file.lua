-- Local image files. PNGs within the size limit are shown as they are; other formats (and
-- oversized PNGs) are converted to a cached PNG with sips (macOS), rsvg-convert (svg) or
-- ImageMagick.
local pipeline = require('inkmd.image.pipeline')

local M = {}

--- Absolute path of image `src` referenced from `buf`, or nil for remote or missing files.
---@param buf integer
---@param src string
---@return string?
function M.resolve(buf, src)
  if src:match('^%a[%w+.-]*://') or src:match('^data:') then
    return nil
  end
  src = src:gsub('^<(.*)>$', '%1'):gsub('%%20', ' ')
  local path
  if src:sub(1, 1) == '/' then
    path = src
  elseif src:sub(1, 1) == '~' then
    path = vim.fn.expand(src)
  else
    local name = vim.api.nvim_buf_get_name(buf)
    local dir = name ~= '' and vim.fs.dirname(name) or vim.fn.getcwd()
    path = vim.fs.normalize(vim.fs.joinpath(dir, src))
  end
  return vim.uv.fs_stat(path) and path or nil
end

---@param path string
function M.key(path)
  local stat = vim.uv.fs_stat(path)
  return vim.fn.sha256(table.concat({ 'file', path, stat and stat.mtime.sec or 0, stat and stat.size or 0 }, '\0'))
end

local function convert_argv(path, max)
  local ext = path:match('%.(%w+)$')
  ext = ext and ext:lower() or ''
  if ext == 'svg' then
    return { 'rsvg-convert', '--keep-aspect-ratio', '-w', tostring(max), '-o', '{out}', path }
  elseif vim.fn.executable('sips') == 1 then
    -- No -Z here: sips would also enlarge small images. Oversized results shrink after.
    return { 'sips', '-s', 'format', 'png', path, '--out', '{out}' }
  else
    return { 'magick', path .. '[0]', '-resize', max .. 'x' .. max .. '>', '{out}' }
  end
end

--- Job that makes a displayable PNG for `path`.
---@param path string
---@param key string
---@param max_pixels integer
function M.job(path, key, max_pixels)
  return function(done)
    local result = pipeline.from_png(path)
    if result and math.max(result.width, result.height) <= max_pixels then
      return done(result)
    end
    local out = pipeline.cache_path(key)
    local function parse_error(output)
      return vim.trim(output) ~= '' and vim.trim(output) or 'cannot convert ' .. path
    end
    pipeline.run(convert_argv(path, max_pixels), out, 30000, parse_error, function(res)
      if res.status == 'ok' and math.max(res.width, res.height) > max_pixels and vim.fn.executable('sips') == 1 then
        return pipeline.run({ 'sips', '-Z', tostring(max_pixels), out, '--out', '{out}' }, out, 30000, parse_error, done)
      end
      done(res)
    end)
  end
end

return M
