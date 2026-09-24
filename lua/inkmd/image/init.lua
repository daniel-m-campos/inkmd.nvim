-- Images and Mermaid diagrams, drawn with kitty Unicode placeholders through the claimer
-- API: the core reserves the rows, this module fills them.
local cell = require('inkmd.image.cell')
local config = require('inkmd.config')
local detect = require('inkmd.image.detect')
local file = require('inkmd.image.convert.file')
local fit = require('inkmd.image.fit')
local hooks = require('inkmd.hooks')
local kitty = require('inkmd.image.kitty')
local latex = require('inkmd.image.convert.latex')
local mermaid = require('inkmd.image.convert.mermaid')
local pad = require('inkmd.image.pad')
local pipeline = require('inkmd.image.pipeline')
local placeholder = require('inkmd.image.placeholder')

local M = {}

-- Last drawing per buffer and block start row: shown while a changed diagram re-renders,
-- so the layout doesn't jump and the preview stays up while editing.
---@type table<integer, table<integer, inkmd.ImageResult>>
local last = {}
---@type table<string, uv.uv_timer_t>
local timers = {}

local function refresh(buf)
  if vim.api.nvim_buf_is_valid(buf) and require('inkmd.state').get(buf) then
    require('inkmd').refresh(buf)
  end
end

--- Largest box for a drawing in `buf`, in cells.
local function box(ctx, indent)
  local opts = config.options.image
  local height = math.huge
  for _, win in ipairs(vim.fn.win_findbuf(ctx.buf)) do
    height = math.min(height, vim.api.nvim_win_get_height(win))
  end
  if height == math.huge then
    height = vim.o.lines
  end
  return math.min(ctx.avail - indent, opts.max_width), math.min(opts.max_height, height - 3)
end

---@param result inkmd.ImageResult
---@param center? boolean centre the picture in the window (formulas)
local function draw(ctx, result, indent, center)
  local max_cols, max_rows = box(ctx, indent)
  local size = cell.size()
  local cols, rows = fit.cells(result.width, result.height, size, max_cols, max_rows)
  -- Terminals stretch pictures to fill the box: show a copy padded to the box's exact shape
  -- once it's ready (the unpadded picture meanwhile).
  local path = result.path
  if pad.available() and pad.needed(result, cols, rows, size) then
    local key = pad.key(result, cols, rows, size)
    local padded = pipeline.request(key, pad.job(result, key, cols, rows, size), function()
      refresh(ctx.buf)
    end)
    if padded.status == 'ok' then
      path = padded.path
    end
  end
  local id = kitty.image(path, cols, rows)
  if center then
    indent = indent + math.floor((max_cols - cols) / 2)
  end
  return placeholder.virt_lines(id, cols, rows, indent)
end

local function message_lines(text, group, indent, max)
  local lines = {}
  local pad = string.rep(' ', indent)
  for line in text:gmatch('[^\n]+') do
    if #lines == max then
      break
    end
    lines[#lines + 1] = { { pad .. line, group } }
  end
  return lines
end

--- Start the job for `key` now, or after the debounce when the block already has a drawing
--- (it is being edited: don't run mmdc on every keystroke).
local function start(buf, row, key, job, debounce)
  local on_done = function()
    refresh(buf)
  end
  if not debounce then
    pipeline.request(key, job, on_done)
    return
  end
  local id = buf .. ':' .. row
  local timer = timers[id] or vim.uv.new_timer()
  timers[id] = timer
  timer:stop()
  timer:start(debounce, 0, vim.schedule_wrap(function()
    pipeline.request(key, job, on_done)
  end))
end

--- Claim for a rendered block (a diagram, a formula): the picture replaces the source, stays
--- below it while the block is edited, and the last good picture stays up while a changed
--- source re-renders.
---@param item inkmd.Item
---@param ctx inkmd.Ctx
---@param key string
---@param job fun(done: fun(result: inkmd.ImageResult))
---@param opts {debounce: integer, pending: string, center?: boolean}
---@return inkmd.Claim
local function claim_rendered(item, ctx, key, job, opts)
  local buf, indent = item.buf, item.col or 0
  last[buf] = last[buf] or {}
  local prev = last[buf][item.s]
  local result = pipeline.get(key)
  if not result then
    start(buf, item.s, key, job, prev and opts.debounce or nil)
    result = { status = 'pending' }
  end

  if result.status == 'ok' then
    last[buf][item.s] = result
  elseif result.status == 'error' then
    return {
      key = key,
      mode = 'below',
      on_raw = 'keep',
      lines = function()
        return message_lines(result.message, 'DiagnosticError', indent, 3)
      end,
    }
  end
  local shown = result.status == 'ok' and result or prev
  if not shown then
    return {
      key = key,
      mode = 'below',
      on_raw = 'keep',
      lines = function()
        return message_lines(opts.pending, 'Comment', indent, 1)
      end,
    }
  end
  return {
    key = key,
    mode = 'replace',
    on_raw = 'keep',
    lines = function()
      return draw(ctx, shown, indent, opts.center)
    end,
  }
end

---@param item inkmd.Item
---@param ctx inkmd.Ctx
---@return inkmd.Claim?
local function claim_mermaid(item, ctx)
  local opts = config.options.image.mermaid
  if not opts.enabled or not vim.tbl_contains(opts.langs, item.lang) then
    return nil
  end
  local key = mermaid.key(item.text, opts)
  return claim_rendered(item, ctx, key, mermaid.job(item.text, key, opts), {
    debounce = opts.debounce,
    pending = '⋯ rendering mermaid…',
  })
end

---@param item inkmd.Item
---@param ctx inkmd.Ctx
---@return inkmd.Claim?
local function claim_math(item, ctx)
  local opts = config.options.math
  if not opts.display then
    return nil
  end
  local color = latex.color()
  local dpi = latex.dpi(cell.size().height, opts.scale)
  local key = latex.key(item.text, opts, color, dpi)
  return claim_rendered(item, ctx, key, latex.job(item.text, key, opts, color, dpi), {
    debounce = opts.debounce,
    pending = '⋯ typesetting…',
    center = true,
  })
end

---@param item inkmd.Item
---@param ctx inkmd.Ctx
---@return inkmd.Claim?
local function claim_image(item, ctx)
  local opts = config.options.image
  if not opts.files or not item.src then
    return nil
  end
  local path = file.resolve(item.buf, item.src)
  if not path then
    return nil
  end
  local key = file.key(path)
  local result = pipeline.request(key, file.job(path, key, opts.max_pixels), function()
    refresh(item.buf)
  end)
  local indent = item.col or 0
  if result.status == 'ok' then
    return {
      key = key,
      mode = 'below',
      on_raw = 'keep',
      lines = function()
        return draw(ctx, result, indent)
      end,
    }
  elseif result.status == 'error' then
    return {
      key = key,
      mode = 'below',
      on_raw = 'keep',
      lines = function()
        return message_lines(result.message, 'DiagnosticError', indent, 3)
      end,
    }
  end
end

--- The claimer; returns nothing when the terminal can't show images, leaving code blocks
--- and alt text to the text renderer.
---@param item inkmd.Item
---@param ctx inkmd.Ctx
function M.claim(item, ctx)
  local opts = config.options.image
  if not opts.enabled or detect.unavailable(opts.backend) then
    return nil
  end
  if item.kind == 'code' then
    return claim_mermaid(item, ctx)
  elseif item.kind == 'math' then
    return claim_math(item, ctx)
  elseif item.kind == 'image' then
    return claim_image(item, ctx)
  end
end

--- Forget drawings and send everything again.
function M.refresh_all()
  kitty.clear()
  pipeline.reset()
  cell.reset()
  last = {}
  for _, buf in ipairs(require('inkmd.state').buffers()) do
    refresh(buf)
  end
end

local registered = false

function M.setup()
  if registered then
    return
  end
  registered = true
  pipeline.max_jobs = config.options.image.mermaid.max_jobs
  hooks.register_claimer({ kinds = { 'code', 'image', 'math' }, claim = M.claim })

  local group = vim.api.nvim_create_augroup('inkmd_image', { clear = true })
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      kitty.clear()
    end,
  })
  vim.api.nvim_create_autocmd('TermResponse', {
    group = group,
    callback = function(ev)
      local seq = ev.data and ev.data.sequence
      if seq and seq:sub(1, 3) == '\027_G' then
        kitty.on_response(seq)
      end
    end,
  })
  -- The UI (and 'termguicolors') may attach after the first render; the theme follows
  -- 'background'; the cell size follows the font and window size.
  vim.api.nvim_create_autocmd('UIEnter', {
    group = group,
    callback = function()
      vim.schedule(function()
        for _, buf in ipairs(require('inkmd.state').buffers()) do
          refresh(buf)
        end
      end)
    end,
  })
  vim.api.nvim_create_autocmd('OptionSet', {
    group = group,
    pattern = 'background',
    callback = function()
      for _, buf in ipairs(require('inkmd.state').buffers()) do
        refresh(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function()
      cell.reset()
    end,
  })
  vim.api.nvim_create_user_command('InkmdImageRefresh', M.refresh_all, { desc = 'Re-render and resend all images' })
  vim.api.nvim_create_user_command('InkmdImageOpen', function()
    local buf = vim.api.nvim_get_current_buf()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local best
    for s, result in pairs(last[buf] or {}) do
      if s <= row and (not best or s > best) and result.path then
        best = s
      end
    end
    if best then
      vim.ui.open(last[buf][best].path)
    else
      vim.notify('inkmd: no rendered diagram at or above the cursor', vim.log.levels.WARN)
    end
  end, { desc = 'Open the diagram under the cursor in the system viewer' })
end

return M
