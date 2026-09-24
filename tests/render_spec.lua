local h = require('helpers')

describe('render', function()
  it('renders headings, lists, checkboxes, code and inline markers', function()
    h.open('basic.md', { 21, 0 })
    h.golden('basic', h.screen())
  end)

  it('sets window options and paints heading and code backgrounds', function()
    local buf = h.open('basic.md', { 21, 0 })
    h.eq(vim.wo.conceallevel, 3)
    h.eq(vim.wo.concealcursor, '')
    h.truthy(#h.marks_with_hl(buf, 0, 'InkmdH1Bg') == 1, 'H1 background on row 0')
    h.truthy(#h.marks_with_hl(buf, 13, 'InkmdCode') == 1, 'code background on the first body row')
  end)

  it('keeps the code label and borders within a narrow window', function()
    h.narrow(30)
    h.open('basic.md', { 21, 0 })
    local screen = h.screen(nil, 30)
    local border = vim.tbl_filter(function(line)
      return line:find('▀', 1, true) ~= nil
    end, screen)[1]
    h.eq(vim.fn.strdisplaywidth(border), 30)
    -- Body rows are checked through their marks: after some earlier tests the headless grid
    -- keeps stale cells in this split (not reproducible outside the runner).
    local pad = vim.tbl_filter(function(m)
      return m[4].virt_text_win_col ~= nil
    end, h.marks(vim.api.nvim_get_current_buf()))
    h.truthy(#pad > 0 and pad[1][4].virt_text_win_col + vim.fn.strdisplaywidth(pad[1][4].virt_text[1][1]) <= 30, 'padding fits')
  end)

  it('renders code blocks nested in lists from the fence column', function()
    h.scratch({ '- item', '', '  ```sh', '  echo hi', '  ```', '', 'end' }, { 7, 0 })
    local screen = h.screen(5)
    h.eq(screen[4], '    echo hi')
    h.truthy(screen[3]:find('sh', 1, true), 'label shown: ' .. screen[3])
  end)

  it('draws heading borders over blank neighbours only', function()
    h.narrow(20)
    h.scratch({ 'text', '', '## Head', 'text right after', '', 'end' }, { 6, 0 })
    local screen = h.screen(nil, 20)
    h.eq(screen[2], string.rep('▄', 20))
    h.eq(screen[4], 'text right after')
    local config = require('inkmd.config')
    config.options.heading.border = false
    require('inkmd').render_now(0)
    screen = h.screen(nil, 20)
    config.options.heading.border = true
    h.eq(screen[2], '')
  end)
end)
