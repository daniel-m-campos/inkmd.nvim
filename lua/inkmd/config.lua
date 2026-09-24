local M = {}

---@class inkmd.Config
M.defaults = {
  enabled = true,
  filetypes = { 'markdown' },
  max_file_size = 2 * 1024 * 1024,
  debounce = 60,
  -- Show the block under the cursor as raw markdown while everything else stays rendered.
  hybrid = true,
  win_options = {
    conceallevel = 3,
    concealcursor = '',
    breakindent = true,
    breakindentopt = 'list:-1',
  },
  heading = {
    icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
    -- 'full' paints the whole line, 'none' leaves the background alone.
    background = 'full',
  },
  code = {
    left_pad = 2,
    right_pad = 2,
    min_width = 40,
    -- 'thin' draws half-block rules above and below the block; 'none' just hides the fences.
    border = 'thin',
    label = true,
  },
  list = {
    bullets = { '●', '○', '◆', '◇' },
  },
  -- The space after "[ ]" is kept, so icons carry no trailing space.
  checkbox = {
    unchecked = '󰄱',
    checked = '󰱒',
  },
}

---@type inkmd.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend('force', vim.deepcopy(M.defaults), opts or {})
end

return M
