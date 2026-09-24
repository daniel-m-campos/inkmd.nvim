local h = require('helpers')
local hooks = require('inkmd.hooks')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

--- Claims ```fake blocks (replace, live preview) and images (below).
local function fake()
  return hooks.register_claimer({
    kinds = { 'code', 'image' },
    claim = function(item)
      if item.kind == 'code' and item.lang == 'fake' then
        return {
          key = item.text,
          mode = 'replace',
          on_raw = 'keep',
          lines = function()
            return { { { '[diagram: ' .. item.text .. ']', 'Normal' } } }
          end,
        }
      elseif item.kind == 'image' then
        return {
          key = item.src,
          mode = 'below',
          on_raw = 'keep',
          lines = function()
            return { { { '[image ' .. item.src .. ']', 'Normal' } } }
          end,
        }
      end
    end,
  })
end

describe('claimers', function()
  it('replaces a claimed code block with its lines', function()
    local unregister = fake()
    local ok, err = pcall(function()
      h.scratch({ 'before', '```fake', 'A --> B', '```', 'after' }, { 1, 0 })
      h.eq(h.screen(), { 'before', '[diagram: A --> B]', 'after' })
    end)
    unregister()
    assert(ok, err)
  end)

  it('shows the source with the drawing below it while the cursor is in the block', function()
    local unregister = fake()
    local ok, err = pcall(function()
      h.scratch({ 'before', '```fake', 'A --> B', '```', 'after' }, { 1, 0 })
      move(3)
      h.eq(h.screen(), { 'before', '```fake', 'A --> B', '```', '[diagram: A --> B]', 'after' })
      move(1)
      h.eq(h.screen(), { 'before', '[diagram: A --> B]', 'after' })
    end)
    unregister()
    assert(ok, err)
  end)

  it('draws above the block when it ends the buffer', function()
    local unregister = fake()
    local ok, err = pcall(function()
      h.scratch({ 'before', '```fake', 'x', '```' }, { 1, 0 })
      h.eq(h.screen(), { 'before', '[diagram: x]' })
    end)
    unregister()
    assert(ok, err)
  end)

  it('draws claimed images below their paragraph', function()
    local unregister = fake()
    local ok, err = pcall(function()
      h.scratch({ 'see ![alt](a.png)', 'more text', '', 'end' }, { 4, 0 })
      h.eq(h.screen(), { 'see 󰋩 alt', 'more text', '[image a.png]', '', 'end' })
    end)
    unregister()
    assert(ok, err)
  end)

  it('leaves unclaimed elements to the normal handlers', function()
    local unregister = fake()
    local ok, err = pcall(function()
      h.scratch({ '```lua', 'x', '```', '', 'end' }, { 5, 0 })
      h.truthy(h.screen()[1]:find('lua', 1, true), 'lua block rendered normally')
    end)
    unregister()
    assert(ok, err)
  end)
end)
