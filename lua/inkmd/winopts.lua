-- Window-local options while a window shows a rendered buffer. The user's values are
-- saved per window and put back when rendering stops or the window shows another buffer.
local config = require('inkmd.config')

local M = {}

---@param win integer
---@param buf integer
function M.apply(win, buf)
  if vim.w[win].inkmd_saved then
    return
  end
  local saved = {}
  for name, value in pairs(config.options.win_options) do
    saved[name] = vim.api.nvim_get_option_value(name, { win = win })
    vim.api.nvim_set_option_value(name, value, { scope = 'local', win = win })
  end
  vim.w[win].inkmd_saved = saved
  vim.w[win].inkmd_buf = buf
end

---@param win integer
function M.restore(win)
  local saved = vim.w[win].inkmd_saved
  if not saved then
    return
  end
  for name, value in pairs(saved) do
    vim.api.nvim_set_option_value(name, value, { scope = 'local', win = win })
  end
  vim.w[win].inkmd_saved = nil
  vim.w[win].inkmd_buf = nil
end

--- Restore every window currently showing `buf`.
function M.restore_buf(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.w[win].inkmd_buf == buf then
      M.restore(win)
    end
  end
end

return M
