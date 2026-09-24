local config = require('inkmd.config')
local hl = require('inkmd.hl')
local hybrid = require('inkmd.hybrid')
local render = require('inkmd.render')
local state = require('inkmd.state')
local ts = require('inkmd.ts')
local winopts = require('inkmd.winopts')

local M = {}

local initialized = false
-- Whether buffers attached from now on start rendered (`:Inkmd! enable|disable`).
local default_enabled

local function init()
  if initialized then
    return
  end
  initialized = true
  default_enabled = config.options.enabled
  ts.strip_bundled_conceal()
  hl.setup()

  local group = vim.api.nvim_create_augroup('inkmd', { clear = true })
  vim.api.nvim_create_autocmd('ColorScheme', {
    group = group,
    callback = function()
      hl.setup()
    end,
  })
  -- A window that stops showing a rendered buffer gets the user's options back.
  vim.api.nvim_create_autocmd('BufWinEnter', {
    group = group,
    callback = function(ev)
      local win = vim.api.nvim_get_current_win()
      local owner = vim.w[win].inkmd_buf
      if owner and owner ~= ev.buf then
        winopts.restore(win)
      end
    end,
  })
  vim.api.nvim_create_autocmd({ 'WinScrolled', 'WinResized' }, {
    group = group,
    callback = function()
      local seen = {}
      for key in pairs(vim.v.event) do
        local win = tonumber(key)
        if win and vim.api.nvim_win_is_valid(win) then
          local buf = vim.api.nvim_win_get_buf(win)
          if not seen[buf] and state.get(buf) then
            seen[buf] = true
            render.render(buf)
          end
        end
      end
    end,
  })
end

---@param opts? table
function M.setup(opts)
  config.setup(opts)
  initialized = false
  init()
  for _, buf in ipairs(state.buffers()) do
    M.refresh(buf)
  end
end

--- Render now, bypassing the debounce. Tests and callers that need a settled buffer use this.
function M.render_now(buf)
  render.render(buf == 0 and vim.api.nvim_get_current_buf() or buf, true)
end

--- Re-render from scratch (after a config or colour change).
function M.refresh(buf)
  M.render_now(buf)
end

local function schedule(buf)
  local st = state.get(buf)
  if not st then
    return
  end
  st.timer = st.timer or vim.uv.new_timer()
  st.timer:stop()
  st.timer:start(config.options.debounce, 0, vim.schedule_wrap(function()
    render.render(buf)
  end))
end

local function apply_winopts(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    winopts.apply(win, buf)
  end
end

---@param buf integer
function M.attach(buf)
  init()
  if state.get(buf) or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local size = vim.fn.getfsize(vim.api.nvim_buf_get_name(buf))
  if size > config.options.max_file_size then
    return
  end
  local st = state.create(buf, default_enabled)
  st.augroup = vim.api.nvim_create_augroup('inkmd_' .. buf, { clear = true })
  local function on(events, fn)
    vim.api.nvim_create_autocmd(events, { group = st.augroup, buffer = buf, callback = fn })
  end
  on({ 'TextChanged', 'TextChangedI' }, function()
    schedule(buf)
  end)
  on({ 'CursorMoved', 'CursorMovedI' }, function()
    hybrid.update(buf)
  end)
  on('BufWinEnter', function()
    if state.get(buf).enabled then
      apply_winopts(buf)
      render.render(buf)
    end
  end)
  on({ 'BufUnload', 'BufWipeout' }, function()
    M.detach(buf)
  end)
  on('FileType', function(ev)
    if not vim.tbl_contains(config.options.filetypes, ev.match) then
      M.detach(buf)
    end
  end)
  if st.enabled then
    apply_winopts(buf)
    render.render(buf)
  end
end

function M.detach(buf)
  local st = state.get(buf)
  if not st then
    return
  end
  pcall(vim.api.nvim_del_augroup_by_id, st.augroup)
  if vim.api.nvim_buf_is_valid(buf) then
    render.clear(buf)
    winopts.restore_buf(buf)
  end
  state.remove(buf)
end

---@param buf? integer
function M.enable(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = state.get(buf)
  if not st then
    return M.attach(buf)
  end
  st.enabled = true
  apply_winopts(buf)
  render.render(buf, true)
end

---@param buf? integer
function M.disable(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = state.get(buf)
  if not st then
    return
  end
  st.enabled = false
  render.clear(buf)
  winopts.restore_buf(buf)
end

---@param buf? integer
function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local st = state.get(buf)
  if st and st.enabled then
    M.disable(buf)
  else
    M.enable(buf)
  end
end

--- Apply to all attached buffers and set the default for buffers attached later.
---@param action 'enable'|'disable'|'toggle'
function M.all(action)
  init()
  local current = state.get(vim.api.nvim_get_current_buf())
  local enable = action == 'enable' or (action == 'toggle' and not (current and current.enabled))
  default_enabled = enable
  for _, buf in ipairs(state.buffers()) do
    if enable then
      M.enable(buf)
    else
      M.disable(buf)
    end
  end
end

---@return boolean
function M.is_enabled(buf)
  local st = state.get((buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf)
  return st ~= nil and st.enabled
end

return M
