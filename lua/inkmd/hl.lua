-- Highlight groups. Colours are derived from the active colorscheme so any theme works.
local M = {}

local function get(name)
  return vim.api.nvim_get_hl(0, { name = name, link = false })
end

---@param fg integer
---@param bg integer
---@param alpha number share of `fg` in the result
local function blend(fg, bg, alpha)
  local function channel(shift)
    local a = bit.band(bit.rshift(fg, shift), 0xff)
    local b = bit.band(bit.rshift(bg, shift), 0xff)
    return math.floor(a * alpha + b * (1 - alpha) + 0.5)
  end
  return bit.bor(bit.lshift(channel(16), 16), bit.lshift(channel(8), 8), channel(0))
end

local function set(name, spec)
  spec.default = true
  vim.api.nvim_set_hl(0, name, spec)
end

function M.setup()
  local normal = get('Normal')
  local bg, fg = normal.bg, normal.fg
  local fallback_bg = { 'DiffAdd', 'DiffChange', 'DiffDelete', 'DiffText', 'Visual', 'CursorLine' }

  for level = 1, 6 do
    local heading = 'InkmdH' .. level
    set(heading, { link = '@markup.heading.' .. level .. '.markdown' })
    local color = get('@markup.heading.' .. level .. '.markdown').fg
    if bg and color then
      vim.api.nvim_set_hl(0, heading .. 'Bg', { bg = blend(color, bg, 0.15) })
    else
      set(heading .. 'Bg', { link = fallback_bg[level] })
    end
  end

  local code_bg = bg and fg and blend(fg, bg, 0.07) or nil
  if code_bg then
    vim.api.nvim_set_hl(0, 'InkmdCode', { bg = code_bg })
    vim.api.nvim_set_hl(0, 'InkmdCodeInline', { bg = code_bg })
    vim.api.nvim_set_hl(0, 'InkmdCodeBorder', { fg = code_bg })
    vim.api.nvim_set_hl(0, 'InkmdCodeInfo', { fg = get('@label').fg, bg = code_bg, italic = true })
  else
    set('InkmdCode', { link = 'ColorColumn' })
    set('InkmdCodeInline', { link = 'ColorColumn' })
    set('InkmdCodeBorder', { link = 'NonText' })
    set('InkmdCodeInfo', { link = '@label' })
  end
  if bg and fg then
    vim.api.nvim_set_hl(0, 'InkmdTableRowAlt', { bg = blend(fg, bg, 0.04) })
  else
    set('InkmdTableRowAlt', { link = 'CursorLine' })
  end

  local warn = get('DiagnosticWarn').fg
  if bg and warn then
    vim.api.nvim_set_hl(0, 'InkmdHighlight', { bg = blend(warn, bg, 0.3) })
  else
    set('InkmdHighlight', { link = 'Search' })
  end

  set('InkmdBullet', { link = '@markup.list' })
  set('InkmdLink', { link = '@markup.link.label' })
  set('InkmdLinkIcon', { link = '@markup.link' })
  set('InkmdFootnote', { link = '@markup.link' })
  set('InkmdQuote', { link = '@markup.quote' })
  set('InkmdNote', { link = 'DiagnosticInfo' })
  set('InkmdTip', { link = 'DiagnosticOk' })
  set('InkmdImportant', { link = 'DiagnosticHint' })
  set('InkmdWarning', { link = 'DiagnosticWarn' })
  set('InkmdCaution', { link = 'DiagnosticError' })
  set('InkmdRule', { link = 'LineNr' })
  set('InkmdTableBorder', { link = 'LineNr' })
  set('InkmdTableHead', { link = '@markup.strong' })
  set('InkmdMath', { link = '@markup.math' })
  set('InkmdUnchecked', { link = '@markup.list.unchecked' })
  set('InkmdChecked', { link = '@markup.list.checked' })
end

return M
