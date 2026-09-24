-- Which image backend the terminal supports. Checked lazily: during startup no UI may be
-- attached yet, and 'termguicolors' is only settled after the TUI attaches.
local M = {}

--- Why graphics are unavailable, or nil when kitty graphics can be used.
---@param setting 'auto'|'kitty'|'text'
---@return string? reason
function M.unavailable(setting)
  if setting == 'text' then
    return 'image.backend is "text"'
  elseif setting == 'kitty' then
    return nil
  end
  if #vim.api.nvim_list_uis() == 0 then
    return 'no UI attached'
  end
  if not vim.o.termguicolors then
    return "'termguicolors' is off (placeholder cells carry the image id as a 24-bit colour)"
  end
  if vim.env.TMUX then
    return 'tmux is not supported (it strips kitty placeholders unless configured for passthrough)'
  end
  local term = (vim.env.TERM or '') .. ' ' .. (vim.env.TERM_PROGRAM or '')
  -- herdr sets TERM_PROGRAM from the outer terminal, so its own marker comes first.
  if vim.env.HERDR_ENV or vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR or term:match('kitty') or term:match('ghostty') then
    return nil
  end
  return 'terminal not recognised as kitty, ghostty or herdr'
end

return M
