-- Terminals stretch a picture to fill its cell box, and whole cells rarely have the
-- picture's exact shape (a formula 31 px tall gets 2 rows = 68 px). So pictures are padded
-- with transparent margins to the box's exact pixel size, centred, and then shown 1:1.
-- Padding wraps the PNG in an SVG of the box size and renders it with rsvg-convert.
local pipeline = require('inkmd.image.pipeline')

local M = {}

--- Pixel size of a cols x rows box.
local function box_px(cols, rows, cell)
  return math.floor(cols * cell.width + 0.5), math.floor(rows * cell.height + 0.5)
end

--- Whether `result` needs padding to fill the box without distortion (more than 1% off).
---@param result inkmd.ImageResult
function M.needed(result, cols, rows, cell)
  local w, h = box_px(cols, rows, cell)
  local image, box = result.width / result.height, w / h
  return math.abs(box / image - 1) > 0.01
end

---@param result inkmd.ImageResult
function M.key(result, cols, rows, cell)
  local w, h = box_px(cols, rows, cell)
  return vim.fn.sha256(table.concat({ 'pad', result.path, w, h }, '\0'))
end

--- Job writing `result` centred in a transparent PNG of the box size.
---@param result inkmd.ImageResult
function M.job(result, key, cols, rows, cell)
  return function(done)
    local w, h = box_px(cols, rows, cell)
    -- Keep the aspect ratio; shrink only if the picture is larger than the box.
    local scale = math.min(w / result.width, h / result.height, 1)
    local iw, ih = result.width * scale, result.height * scale
    local f = io.open(result.path, 'rb')
    if not f then
      return done({ status = 'error', message = 'cannot read ' .. result.path })
    end
    local data = vim.base64.encode(f:read('*a'))
    f:close()
    local out = pipeline.cache_path(key)
    local svg_path = out .. '.svg'
    local svg = io.open(svg_path, 'w')
    if not svg then
      return done({ status = 'error', message = 'cannot write ' .. svg_path })
    end
    svg:write(string.format(
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" '
        .. 'width="%d" height="%d" viewBox="0 0 %d %d"><image x="%.2f" y="%.2f" width="%.2f" '
        .. 'height="%.2f" preserveAspectRatio="none" xlink:href="data:image/png;base64,%s"/></svg>',
      w, h, w, h, (w - iw) / 2, (h - ih) / 2, iw, ih, data
    ))
    svg:close()
    pipeline.run({ 'rsvg-convert', '-o', '{out}', svg_path }, out, 30000, function(output)
      return vim.trim(output) ~= '' and vim.trim(output) or 'rsvg-convert failed'
    end, function(res)
      os.remove(svg_path)
      done(res)
    end)
  end
end

--- Available (rsvg-convert installed).
function M.available()
  return vim.fn.executable('rsvg-convert') == 1
end

return M
