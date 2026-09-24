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
    { 'latex', 'display math (TeX Live or MacTeX)' },
    { 'dvipng', 'display math (TeX Live or MacTeX)' },
  }
  for _, tool in ipairs(tools) do
    if vim.fn.executable(tool[1]) == 1 then
      health.ok(tool[1] .. ': ' .. tool[2])
    else
      health.info(tool[1] .. ' not found: ' .. tool[2])
    end
  end
  local opts = require('inkmd.config').options.image
  local reason = require('inkmd.image.detect').unavailable(opts.backend)
  if not opts.enabled then
    health.info('images disabled (image.enabled = false)')
  elseif reason then
    health.warn('images fall back to text: ' .. reason)
  else
    local where = vim.env.HERDR_ENV and 'herdr' or vim.env.KITTY_WINDOW_ID and 'kitty' or 'ghostty/kitty-compatible'
    health.ok('images drawn with kitty graphics (' .. where .. ', Unicode placeholders)')
    local cell = require('inkmd.image.cell').size()
    health.info(string.format('cell size: %.1f x %.1f px', cell.width, cell.height))
  end
end

return M
