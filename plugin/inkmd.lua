if vim.g.loaded_inkmd then
  return
end
vim.g.loaded_inkmd = true

vim.api.nvim_create_user_command('Inkmd', function(o)
  local action = o.fargs[1] or 'toggle'
  if not vim.tbl_contains({ 'toggle', 'enable', 'disable' }, action) then
    vim.notify('inkmd: unknown action ' .. action, vim.log.levels.ERROR)
    return
  end
  local inkmd = require('inkmd')
  if o.bang then
    inkmd.all(action)
  else
    inkmd[action](0)
  end
end, {
  nargs = '?',
  bang = true,
  complete = function()
    return { 'toggle', 'enable', 'disable' }
  end,
  desc = 'Toggle markdown rendering (! for all buffers)',
})

vim.keymap.set('n', '<Plug>(InkmdToggle)', function()
  require('inkmd').toggle(0)
end, { desc = 'Toggle markdown rendering' })

local function attach_if_markdown(buf)
  local filetypes = require('inkmd.config').options.filetypes
  if vim.tbl_contains(filetypes, vim.bo[buf].filetype) then
    require('inkmd').attach(buf)
  end
end

vim.api.nvim_create_autocmd('FileType', {
  group = vim.api.nvim_create_augroup('inkmd_attach', { clear = true }),
  callback = function(ev)
    attach_if_markdown(ev.buf)
  end,
})

-- Buffers that got their filetype before this file was sourced.
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(buf) then
    attach_if_markdown(buf)
  end
end
