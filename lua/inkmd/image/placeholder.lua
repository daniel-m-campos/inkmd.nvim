-- Kitty Unicode placeholders: each cell is U+10EEEE plus a row and a column diacritic, and
-- the foreground colour carries the image id. Neovim draws them as ordinary text, so the
-- picture scrolls, splits and clips with the buffer.
local diacritics = require('inkmd.image.diacritics')

local M = {}

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)
local marks = {}
for i, cp in ipairs(diacritics) do
  marks[i] = vim.fn.nr2char(cp)
end

--- Highlight group whose foreground encodes `id` (24 bits).
---@param id integer
function M.hl(id)
  local name = string.format('InkmdImage%06x', id)
  vim.api.nvim_set_hl(0, name, { fg = id, nocombine = true })
  return name
end

--- Rows of placeholder text for image `id` placed in `cols` x `rows` cells.
---@return string[]
function M.rows(cols, rows)
  cols, rows = math.min(cols, #marks), math.min(rows, #marks)
  local out = {}
  for r = 1, rows do
    local cells = {}
    for c = 1, cols do
      cells[c] = PLACEHOLDER .. marks[r] .. marks[c]
    end
    out[r] = table.concat(cells)
  end
  return out
end

--- Virtual lines drawing image `id` at `indent` columns.
---@return [string, string|string[]][][]
function M.virt_lines(id, cols, rows, indent)
  local group = M.hl(id)
  local pad = string.rep(' ', indent or 0)
  local lines = {}
  for i, text in ipairs(M.rows(cols, rows)) do
    lines[i] = indent and indent > 0 and { { pad }, { text, group } } or { { text, group } }
  end
  return lines
end

return M
