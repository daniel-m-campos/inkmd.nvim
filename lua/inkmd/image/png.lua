-- PNG header parsing: the pixel size without decoding the image.
local M = {}

local SIGNATURE = '\137PNG\r\n\26\n'

local function u32(s, i)
  local a, b, c, d = s:byte(i, i + 3)
  return ((a * 256 + b) * 256 + c) * 256 + d
end

--- Width and height of a PNG file, or nil if it isn't one.
---@param path string
---@return integer? width, integer? height
function M.size(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local header = f:read(24)
  f:close()
  -- Signature (8), IHDR length (4), "IHDR" (4), width (4), height (4).
  if not header or #header < 24 or header:sub(1, 8) ~= SIGNATURE or header:sub(13, 16) ~= 'IHDR' then
    return nil
  end
  return u32(header, 17), u32(header, 21)
end

return M
