local h = require('helpers')

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

local LINK = 'see [the docs](https://example.com/a/very/long/path/that/is/hidden) now'

describe('reflow', function()
  it('wraps a line with a hidden URL by its rendered width', function()
    h.narrow(40)
    h.scratch({ 'x', LINK .. ' and some more words here', '', 'end' }, { 4, 0 })
    local screen = h.screen(nil, 40)
    -- Rendered: "see 󰖟 the docs now and some more words here" (44 cells) in 40 columns.
    h.eq(screen[2], 'see 󰖟 the docs now and some more words')
    h.eq(screen[3], 'here')
    h.eq(screen[4], '')
  end)

  it('keeps short rendered lines on one row', function()
    h.narrow(50)
    h.scratch({ 'x', LINK, '', 'end' }, { 4, 0 })
    local screen = h.screen(nil, 50)
    h.eq(screen[2], 'see 󰖟 the docs now')
    h.eq(screen[3], '')
  end)

  it('hangs wrapped list item text under the bullet', function()
    h.narrow(30)
    h.scratch({ 'x', '- ' .. LINK .. ' and more', '', 'end' }, { 4, 0 })
    local screen = h.screen(nil, 30)
    h.eq(screen[2], '● see 󰖟 the docs now and more')
    h.narrow(22)
    require('inkmd').render_now(0)
    screen = h.screen(nil, 22)
    h.eq(screen[2], '● see 󰖟 the docs now')
    h.eq(screen[3], '  and more')
  end)

  it('keeps quote bars on wrapped lines', function()
    h.narrow(22)
    h.scratch({ 'x', '> ' .. LINK .. ' and more', '', 'end' }, { 4, 0 })
    local screen = h.screen(nil, 22)
    h.eq(screen[2], '▋ see 󰖟 the docs now')
    h.eq(screen[3], '▋ and more')
  end)

  it('shows the paragraph raw with the cursor in it', function()
    h.narrow(40)
    h.scratch({ 'x', LINK, '', 'end' }, { 4, 0 })
    move(2)
    local screen = h.screen(nil, 40)
    h.eq(screen[2], LINK:sub(1, 40))
  end)

  it('works for a paragraph at the end of the buffer', function()
    h.narrow(40)
    h.scratch({ 'x', '', LINK .. ' and some more words here' }, { 1, 0 })
    local screen = h.screen(nil, 40)
    h.eq(screen[3], 'see 󰖟 the docs now and some more words')
    h.eq(screen[4], 'here')
  end)

  it('leaves nowrap windows alone', function()
    h.narrow(40)
    vim.wo.wrap = false
    local buf = h.scratch({ 'x', LINK, '', 'end' }, { 4, 0 })
    vim.wo.wrap = false
    require('inkmd').render_now(buf)
    for _, m in ipairs(h.marks(buf)) do
      h.truthy(not m[4].conceal_lines, 'no rows hidden')
    end
  end)
end)
