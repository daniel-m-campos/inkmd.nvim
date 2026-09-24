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
    vim.o.columns = 30
    h.open('basic.md', { 21, 0 })
    local screen = h.screen()
    for _, line in ipairs(screen) do
      h.truthy(vim.fn.strdisplaywidth(line) <= 30, 'line wider than the window: ' .. line)
    end
  end)

  it('renders code blocks nested in lists from the fence column', function()
    h.scratch({ '- item', '', '  ```sh', '  echo hi', '  ```', '', 'end' }, { 7, 0 })
    local screen = h.screen(5)
    h.eq(screen[4], '    echo hi')
    h.truthy(screen[3]:find('sh', 1, true), 'label shown: ' .. screen[3])
  end)
end)
