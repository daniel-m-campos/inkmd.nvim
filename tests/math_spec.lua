local h = require('helpers')
local config = require('inkmd.config')
local kitty = require('inkmd.image.kitty')
local pipeline = require('inkmd.image.pipeline')
local convert = require('inkmd.latex').convert

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

local function with_images(fn)
  local saved_image, saved_math = vim.deepcopy(config.options.image), vim.deepcopy(config.options.math)
  local write = kitty.write
  config.options.image.backend = 'kitty'
  config.options.math.latex = h.root .. '/tests/fixtures/fake-latex'
  config.options.math.dvipng = h.root .. '/tests/fixtures/fake-dvipng'
  pipeline.dir = h.root .. '/tests/.tmp/cache'
  vim.fn.delete(pipeline.dir, 'rf')
  pipeline.reset()
  kitty.write = function() end
  local ok, err = pcall(fn)
  kitty.clear()
  kitty.write = write
  config.options.image, config.options.math = saved_image, saved_math
  pipeline.dir = nil
  pipeline.reset()
  assert(ok, err)
end

local function virt_lines(buf)
  local out = {}
  for _, m in ipairs(h.marks(buf)) do
    for _, line in ipairs(m[4].virt_lines or {}) do
      out[#out + 1] = table.concat(vim.tbl_map(function(c)
        return c[1]
      end, line))
    end
  end
  return out
end

local function has_picture(buf)
  for _, line in ipairs(virt_lines(buf)) do
    if line:find(PLACEHOLDER, 1, true) then
      return true
    end
  end
  return false
end

describe('latex to unicode', function()
  local cases = {
    { [[\alpha^2 \leq \frac{1}{n}]], 'α² ≤ 1/n' },
    { [[x_1, x_2, \ldots, x_n]], 'x₁, x₂, …, xₙ' },
    { [[\sum_{i=1}^{n} i = \frac{n(n+1)}{2}]], '∑ᵢ₌₁ⁿ i = n(n+1)/2' },
    { [[e^{i\pi} + 1 = 0]], 'e^(iπ) + 1 = 0' },
    { [[\frac{a+b}{c}]], '(a+b)/c' },
    { [[\sqrt{2} \cdot \sqrt[3]{8}]], '√2 · ∛8' },
    { [[\mathbb{R}^n \to \mathbb{C}]], 'ℝⁿ → ℂ' },
    { [[\hat{x}]], 'x̂' },
    { [[\left( \frac{a}{b} \right)^2]], '(a/b)²' },
    { [[\text{if } x \in A]], 'if x ∈ A' },
    { [[\unknown{x}]], '\\unknown{x}' },
  }
  for _, case in ipairs(cases) do
    it(case[1], function()
      h.eq(convert(case[1]), case[2])
    end)
  end
end)

describe('math rendering', function()
  it('shows inline math as unicode', function()
    h.scratch({ 'so $\\alpha^2 \\leq \\frac{1}{n}$ holds', '', 'end' }, { 3, 0 })
    h.eq(h.screen()[1], 'so α² ≤ 1/n holds')
  end)

  it('shows inline math raw with the cursor on it', function()
    h.scratch({ 'so $\\alpha$ holds', '', 'end' }, { 1, 0 })
    vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
    h.eq(h.screen()[1], 'so $\\alpha$ holds')
  end)

  it('keeps display math as text without an image backend', function()
    h.scratch({ 'x', '', '$$', 'a^2', '$$', '', 'end' }, { 7, 0 })
    h.eq(h.screen()[4], 'a^2')
  end)

  it('typesets display math into a centred picture', function()
    with_images(function()
      local buf = h.scratch({ 'x', '', '$$', '\\int_0^1 x^2 dx', '$$', '', 'end' }, { 7, 0 })
      h.truthy(vim.wait(5000, function()
        return has_picture(buf)
      end, 20), 'picture drawn: ' .. vim.inspect(virt_lines(buf)))
      local screen = h.screen()
      h.truthy(not vim.tbl_contains(screen, '$$'), 'source hidden')
      -- The 64x32 test picture is 8 cells wide in the headless 8x16 fallback cell: centred.
      local line = vim.tbl_filter(function(l)
        return l:find(PLACEHOLDER, 1, true) ~= nil
      end, virt_lines(buf))[1]
      h.eq(#line:match('^ *'), math.floor((80 - 8) / 2))
    end)
  end)

  it('shows latex errors under the source', function()
    with_images(function()
      local buf = h.scratch({ 'x', '', '$$', '\\error{x}', '$$', '', 'end' }, { 7, 0 })
      h.truthy(vim.wait(5000, function()
        return vim.tbl_contains(virt_lines(buf), '! Undefined control sequence.')
      end, 20), 'error shown: ' .. vim.inspect(virt_lines(buf)))
      h.eq(virt_lines(buf)[2], 'l.6 $\\displaystyle \\error')
      h.truthy(vim.tbl_contains(h.screen(), '\\error{x}'), 'source visible')
    end)
  end)

  it('keeps backslashes inside math', function()
    h.scratch({ 'x', '', '$$', 'a \\\\ b', '$$', '', 'end' }, { 7, 0 })
    h.eq(h.screen()[4], 'a \\\\ b')
  end)

  it('treats $$...$$ inside a sentence as inline math', function()
    with_images(function()
      local buf = h.scratch({ 'see $$x^2$$ here', '', 'end' }, { 3, 0 })
      h.eq(h.screen()[1], 'see x² here')
      h.eq(#virt_lines(buf), 0)
    end)
  end)
end)
