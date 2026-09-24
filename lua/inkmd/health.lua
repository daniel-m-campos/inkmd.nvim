local M = {}

local health = vim.health

function M.check()
  health.start('inkmd: core')
  if vim.fn.has('nvim-0.12') == 1 then
    health.ok('Neovim ' .. tostring(vim.version()))
  else
    health.error('Neovim 0.12 or newer is required (conceal_lines, async parsing)')
  end
  for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
    local ok = pcall(vim.treesitter.language.add, lang)
    if ok then
      health.ok('treesitter parser: ' .. lang)
    else
      health.error('treesitter parser missing: ' .. lang)
    end
  end
  local leftover = false
  for _, lang in ipairs({ 'markdown', 'markdown_inline' }) do
    local query = vim.treesitter.query.get(lang, 'highlights')
    for _, pattern in pairs(query and query.info.patterns or {}) do
      for _, directive in ipairs(pattern) do
        leftover = leftover or directive[2] == 'conceal' or directive[2] == 'conceal_lines'
      end
    end
  end
  if leftover then
    health.warn('markdown highlight queries still conceal; open a markdown buffer first, or another plugin re-set them')
  else
    health.ok('bundled conceal directives stripped')
  end
  if vim.o.termguicolors then
    health.ok('termguicolors is on')
  else
    health.warn('termguicolors is off: blended backgrounds fall back to linked groups')
  end
  local st = require('inkmd.state')
  health.info(string.format('attached buffers: %d', #st.buffers()))

  health.start('inkmd: images and diagrams')
  local claimers = #require('inkmd.hooks').claimers
  health.info(string.format('registered claimers: %d', claimers))
  local tools = {
    { 'mmdc', 'Mermaid diagrams (npm i -g @mermaid-js/mermaid-cli)' },
    { 'rsvg-convert', 'SVG images (brew install librsvg)' },
    { 'sips', 'image conversion on macOS (built in)' },
  }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool[1]) == 1 then
      health.ok(tool[1] .. ': ' .. tool[2])
    else
      health.info(tool[1] .. ' not found: ' .. tool[2])
    end
  end
  local term
  if vim.env.HERDR_ENV then
    term = 'herdr (kitty graphics via Unicode placeholders)'
  elseif vim.env.KITTY_WINDOW_ID then
    term = 'kitty'
  elseif vim.env.GHOSTTY_RESOURCES_DIR then
    term = 'ghostty'
  end
  if term then
    health.ok('terminal graphics: ' .. term)
  else
    health.info('terminal graphics: not detected from the environment')
  end
end

return M
