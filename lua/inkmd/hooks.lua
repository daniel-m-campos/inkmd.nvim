-- Claimers: extensions (images, Mermaid) that take over an element and draw it in
-- reserved virtual lines. The core owns the space; the claimer owns what goes in it.
local M = {}

---@class inkmd.Claim
---@field key string identifies the rendered content (e.g. a content hash)
---@field mode 'below'|'replace' draw under the element, or hide its rows and draw instead
---@field lines fun(avail: integer): [string, string|string[]][][] virtual lines to draw
---@field on_raw? 'hide'|'keep' whether the drawing stays while the element is shown raw

---@class inkmd.Item
---@field kind 'code'|'image'
---@field buf integer
---@field lang? string code: info string language
---@field text? string code: body; image: alt text
---@field src? string image: destination
---@field s integer first row of the element
---@field e integer row after the element

---@class inkmd.Claimer
---@field kinds string[]
---@field claim fun(item: inkmd.Item, ctx: inkmd.Ctx): inkmd.Claim?

---@type inkmd.Claimer[]
M.claimers = {}

--- Register a claimer. Returns a function that unregisters it.
---@param claimer inkmd.Claimer
---@return fun()
function M.register_claimer(claimer)
  table.insert(M.claimers, claimer)
  return function()
    for i, c in ipairs(M.claimers) do
      if c == claimer then
        table.remove(M.claimers, i)
        return
      end
    end
  end
end

local reported = {}

--- First claim any registered claimer makes on `item`.
---@param item inkmd.Item
---@param ctx inkmd.Ctx
---@return inkmd.Claim?
function M.claim(item, ctx)
  for _, claimer in ipairs(M.claimers) do
    if vim.tbl_contains(claimer.kinds, item.kind) then
      local ok, claim = pcall(claimer.claim, item, ctx)
      if not ok then
        if not reported[claim] then
          reported[claim] = true
          vim.notify('inkmd: claimer failed: ' .. tostring(claim), vim.log.levels.WARN)
        end
      elseif claim then
        return claim
      end
    end
  end
end

--- Reserve space for `claim` on the element at rows [s, e) and draw its lines there.
---@param ctx inkmd.Ctx
---@param claim inkmd.Claim
function M.place(ctx, claim, s, e)
  local lines = claim.lines(ctx.avail)
  local keep = claim.on_raw == 'keep'
  if claim.mode ~= 'replace' then
    ctx:virt_lines(e - 1, lines, false, keep)
    return
  end
  -- Lines on a hidden row don't draw, so hang them on a neighbouring visible row.
  if e < vim.api.nvim_buf_line_count(ctx.buf) then
    ctx:conceal_lines(s, e)
    ctx:virt_lines(e, lines, true, keep)
  elseif s > 0 then
    ctx:conceal_lines(s, e)
    ctx:virt_lines(s - 1, lines, false, keep)
  else
    ctx:virt_lines(e - 1, lines, false, keep)
  end
end

return M
