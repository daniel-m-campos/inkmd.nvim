local h = require('helpers')
local inkmd = require('inkmd')

describe('core', function()
  it('leaves no conceal directives in the markdown highlight queries', function()
    h.open('basic.md')
    for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
      local query = vim.treesitter.query.get(lang, 'highlights')
      for _, pattern in pairs(query.info.patterns) do
        for _, directive in ipairs(pattern) do
          h.truthy(directive[2] ~= 'conceal' and directive[2] ~= 'conceal_lines', lang .. ' still conceals')
        end
      end
    end
  end)

  it('re-renders after an edit', function()
    local buf = h.open('basic.md', { 21, 0 })
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { '### Now level three' })
    inkmd.render_now(buf)
    h.eq(h.screen()[1], '󰲥 Now level three')
  end)

  it('renders only around the view in long documents', function()
    local lines = {}
    for i = 1, 3000 do
      lines[i] = i % 10 == 0 and ('## heading ' .. i) or ('text ' .. i)
    end
    local buf = h.scratch(lines, { 1, 0 })
    local max_row = 0
    for _, m in ipairs(h.marks(buf)) do
      max_row = math.max(max_row, m[2])
    end
    h.truthy(max_row < 200, 'rendered far beyond the view: row ' .. max_row)
    vim.cmd('normal! 2001G')
    vim.api.nvim_exec_autocmds('WinScrolled', {})
    inkmd.render_now(buf)
    h.truthy(#h.marks_with_hl(buf, 1999, 'InkmdH2Bg') == 1, 'heading at row 1999 rendered after scrolling')
  end)

  it('uses the narrowest window for widths when a buffer is split', function()
    vim.o.columns = 100
    h.open('basic.md', { 21, 0 })
    vim.cmd('vsplit')
    vim.cmd('vertical resize 30')
    inkmd.render_now(0)
    local narrowest = math.huge
    for _, win in ipairs(vim.fn.win_findbuf(vim.api.nvim_get_current_buf())) do
      narrowest = math.min(narrowest, vim.api.nvim_win_get_width(win))
    end
    local width
    for _, m in ipairs(vim.api.nvim_buf_get_extmarks(0, h.ns, { 15, 0 }, { 15, -1 }, { details = true })) do
      local vt = m[4].virt_text
      if vt and vt[1][1]:find('▀', 1, true) then
        width = vim.fn.strdisplaywidth(vt[1][1])
      end
    end
    h.eq(width, narrowest, 'bottom border width')
  end)

  it('ignores non-markdown buffers', function()
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { '# not markdown' })
    vim.bo.filetype = 'text'
    h.eq(inkmd.is_enabled(0), false)
  end)
end)
