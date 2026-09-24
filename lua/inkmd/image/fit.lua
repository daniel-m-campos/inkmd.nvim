-- Fit a picture into a cell box: the terminal scales the image into the placement, so only
-- the number of columns and rows matters.
local M = {}

---@param px_width integer image width in pixels
---@param px_height integer image height in pixels
---@param cell {width: number, height: number} cell size in pixels
---@param max_cols integer
---@param max_rows integer
---@return integer cols, integer rows
function M.cells(px_width, px_height, cell, max_cols, max_rows)
  max_cols, max_rows = math.max(max_cols, 1), math.max(max_rows, 1)
  -- Natural size first, then shrink to fit, keeping the aspect ratio.
  local cols = math.ceil(px_width / cell.width)
  local ratio = (px_height / cell.height) / (px_width / cell.width)
  if cols > max_cols then
    cols = max_cols
  end
  local rows = math.max(math.ceil(cols * ratio), 1)
  if rows > max_rows then
    rows = max_rows
    cols = math.max(math.floor(rows / ratio), 1)
  end
  return math.max(cols, 1), rows
end

return M
