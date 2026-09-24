-- TeX math to Unicode, for inline math: $\alpha^2 \leq \frac{1}{n}$ -> α² ≤ 1/n.
-- Handles Greek, operators, relations, arrows, \frac, \sqrt, super- and subscripts
-- (Unicode where every character has a form, else ^(...): $e^{i\pi}$ -> e^(iπ)), \mathbb,
-- text and font commands, accents and spacing. Unknown commands are kept as written.
local M = {}

local symbols = {
  -- Greek
  alpha = 'α', beta = 'β', gamma = 'γ', delta = 'δ', epsilon = 'ϵ', varepsilon = 'ε', zeta = 'ζ',
  eta = 'η', theta = 'θ', vartheta = 'ϑ', iota = 'ι', kappa = 'κ', lambda = 'λ', mu = 'μ', nu = 'ν',
  xi = 'ξ', pi = 'π', varpi = 'ϖ', rho = 'ρ', varrho = 'ϱ', sigma = 'σ', varsigma = 'ς', tau = 'τ',
  upsilon = 'υ', phi = 'ϕ', varphi = 'φ', chi = 'χ', psi = 'ψ', omega = 'ω',
  Gamma = 'Γ', Delta = 'Δ', Theta = 'Θ', Lambda = 'Λ', Xi = 'Ξ', Pi = 'Π', Sigma = 'Σ',
  Upsilon = 'Υ', Phi = 'Φ', Psi = 'Ψ', Omega = 'Ω',
  -- Operators
  sum = '∑', prod = '∏', coprod = '∐', int = '∫', iint = '∬', iiint = '∭', oint = '∮',
  pm = '±', mp = '∓', times = '×', div = '÷', cdot = '·', ast = '∗', star = '⋆', circ = '∘',
  bullet = '•', oplus = '⊕', otimes = '⊗', odot = '⊙', cup = '∪', cap = '∩', setminus = '∖',
  wedge = '∧', land = '∧', vee = '∨', lor = '∨', neg = '¬', lnot = '¬', nabla = '∇',
  partial = '∂', infty = '∞', emptyset = '∅', varnothing = '∅', forall = '∀', exists = '∃',
  nexists = '∄', aleph = 'ℵ', hbar = 'ℏ', ell = 'ℓ', Re = 'ℜ', Im = 'ℑ', wp = '℘',
  prime = '′', degree = '°', angle = '∠', triangle = '△', top = '⊤', bot = '⊥', perp = '⊥',
  -- Relations
  leq = '≤', le = '≤', geq = '≥', ge = '≥', neq = '≠', ne = '≠', approx = '≈', equiv = '≡',
  sim = '∼', simeq = '≃', cong = '≅', propto = '∝', ll = '≪', gg = '≫', prec = '≺', succ = '≻',
  ['in'] = '∈', notin = '∉', ni = '∋', subset = '⊂', supset = '⊃', subseteq = '⊆',
  supseteq = '⊇', mid = '∣', parallel = '∥', models = '⊨', vdash = '⊢', dashv = '⊣',
  -- Arrows
  to = '→', rightarrow = '→', leftarrow = '←', gets = '←', leftrightarrow = '↔',
  Rightarrow = '⇒', Leftarrow = '⇐', Leftrightarrow = '⇔', implies = '⟹', impliedby = '⟸',
  iff = '⟺', mapsto = '↦', uparrow = '↑', downarrow = '↓', longrightarrow = '⟶',
  longleftarrow = '⟵', hookrightarrow = '↪',
  -- Delimiters and dots
  langle = '⟨', rangle = '⟩', lceil = '⌈', rceil = '⌉', lfloor = '⌊', rfloor = '⌋',
  lvert = '|', rvert = '|', vert = '|', lVert = '‖', rVert = '‖', Vert = '‖',
  ldots = '…', dots = '…', cdots = '⋯', vdots = '⋮', ddots = '⋱',
  -- Spacing
  quad = '  ', qquad = '    ',
  -- Named functions print as words
  sin = 'sin', cos = 'cos', tan = 'tan', log = 'log', ln = 'ln', exp = 'exp', lim = 'lim',
  max = 'max', min = 'min', sup = 'sup', inf = 'inf', det = 'det', dim = 'dim', gcd = 'gcd',
  arg = 'arg', deg = 'deg', ker = 'ker', Pr = 'Pr',
}

-- Commands whose argument is shown as is (fonts, text).
local passthrough = {
  text = true, textrm = true, textit = true, textbf = true, mbox = true, mathrm = true,
  mathit = true, mathbf = true, mathsf = true, mathtt = true, boldsymbol = true, bm = true,
  operatorname = true, mathcal = true, mathscr = true, mathfrak = true, displaystyle = false,
}

-- Commands that only size delimiters: dropped.
local sizing = {
  left = true, right = true, big = true, Big = true, bigg = true, Bigg = true, bigl = true,
  bigr = true, Bigl = true, Bigr = true, biggl = true, biggr = true, middle = true,
  displaystyle = true, textstyle = true, scriptstyle = true, limits = true, nolimits = true,
}

local accents = {
  hat = '\u{0302}', widehat = '\u{0302}', bar = '\u{0304}', overline = '\u{0305}', vec = '\u{20D7}',
  dot = '\u{0307}', ddot = '\u{0308}', tilde = '\u{0303}', widetilde = '\u{0303}', check = '\u{030C}',
  acute = '\u{0301}', grave = '\u{0300}', breve = '\u{0306}', underline = '\u{0332}',
}

local blackboard = {
  A = '𝔸', B = '𝔹', C = 'ℂ', D = '𝔻', E = '𝔼', F = '𝔽', G = '𝔾', H = 'ℍ', I = '𝕀', J = '𝕁',
  K = '𝕂', L = '𝕃', M = '𝕄', N = 'ℕ', O = '𝕆', P = 'ℙ', Q = 'ℚ', R = 'ℝ', S = '𝕊', T = '𝕋',
  U = '𝕌', V = '𝕍', W = '𝕎', X = '𝕏', Y = '𝕐', Z = 'ℤ', ['1'] = '𝟙',
}

local superscript = {
  ['0'] = '⁰', ['1'] = '¹', ['2'] = '²', ['3'] = '³', ['4'] = '⁴', ['5'] = '⁵', ['6'] = '⁶',
  ['7'] = '⁷', ['8'] = '⁸', ['9'] = '⁹', ['+'] = '⁺', ['-'] = '⁻', ['−'] = '⁻', ['='] = '⁼',
  ['('] = '⁽', [')'] = '⁾', a = 'ᵃ', b = 'ᵇ', c = 'ᶜ', d = 'ᵈ', e = 'ᵉ', f = 'ᶠ', g = 'ᵍ',
  h = 'ʰ', i = 'ⁱ', j = 'ʲ', k = 'ᵏ', l = 'ˡ', m = 'ᵐ', n = 'ⁿ', o = 'ᵒ', p = 'ᵖ', r = 'ʳ',
  s = 'ˢ', t = 'ᵗ', u = 'ᵘ', v = 'ᵛ', w = 'ʷ', x = 'ˣ', y = 'ʸ', z = 'ᶻ', A = 'ᴬ', B = 'ᴮ',
  D = 'ᴰ', E = 'ᴱ', G = 'ᴳ', H = 'ᴴ', I = 'ᴵ', J = 'ᴶ', K = 'ᴷ', L = 'ᴸ', M = 'ᴹ', N = 'ᴺ',
  O = 'ᴼ', P = 'ᴾ', R = 'ᴿ', T = 'ᵀ', U = 'ᵁ', V = 'ⱽ', W = 'ᵂ', ['α'] = 'ᵅ', ['β'] = 'ᵝ',
  ['γ'] = 'ᵞ', ['δ'] = 'ᵟ', ['θ'] = 'ᶿ', ['φ'] = 'ᵠ', ['χ'] = 'ᵡ', ['′'] = '′', [' '] = ' ',
  ['∗'] = '*', ['*'] = '*',
}

local subscript = {
  ['0'] = '₀', ['1'] = '₁', ['2'] = '₂', ['3'] = '₃', ['4'] = '₄', ['5'] = '₅', ['6'] = '₆',
  ['7'] = '₇', ['8'] = '₈', ['9'] = '₉', ['+'] = '₊', ['-'] = '₋', ['−'] = '₋', ['='] = '₌',
  ['('] = '₍', [')'] = '₎', a = 'ₐ', e = 'ₑ', h = 'ₕ', i = 'ᵢ', j = 'ⱼ', k = 'ₖ', l = 'ₗ',
  m = 'ₘ', n = 'ₙ', o = 'ₒ', p = 'ₚ', r = 'ᵣ', s = 'ₛ', t = 'ₜ', u = 'ᵤ', v = 'ᵥ', x = 'ₓ',
  ['β'] = 'ᵦ', ['γ'] = 'ᵧ', ['ρ'] = 'ᵨ', ['φ'] = 'ᵩ', ['χ'] = 'ᵪ', [' '] = ' ',
}

--- Map every character of `s` through `map`, or nil if one has no form there.
local function script(s, map)
  local out = {}
  for _, ch in ipairs(vim.fn.split(s, '\\zs')) do
    local mapped = map[ch]
    if not mapped then
      return nil
    end
    out[#out + 1] = mapped
  end
  return table.concat(out)
end

--- Parenthesize multi-character operands of / and √.
local function operand(s)
  s = vim.trim(s)
  -- Only operands with an operator outside parentheses need them: a+b, not n(n+1) or √π.
  local top = s:gsub('%b()', '')
  if not top:find('[%s+=,/<>-]') and not top:find('−', 1, true) then
    return s
  end
  return '(' .. s .. ')'
end

local convert

--- Read one argument at byte `i`: a {group}, a \command or one character.
---@return string raw, integer next
local function argument(s, i)
  while s:sub(i, i) == ' ' do
    i = i + 1
  end
  local c = s:sub(i, i)
  if c == '{' then
    local depth, j = 1, i + 1
    while j <= #s and depth > 0 do
      local d = s:sub(j, j)
      if d == '\\' then
        j = j + 1
      elseif d == '{' then
        depth = depth + 1
      elseif d == '}' then
        depth = depth - 1
      end
      j = j + 1
    end
    return s:sub(i + 1, j - 2), j
  elseif c == '\\' then
    local name = s:match('^%a+', i + 1)
    local len = name and #name or 1
    return s:sub(i, i + len), i + len + 1
  end
  local len = vim.str_utf_end(s, i) + 1
  return s:sub(i, i + len - 1), i + len
end

---@param s string TeX math (without $ delimiters)
---@return string
function convert(s)
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' then
      local name = s:match('^%a+', i + 1)
      if not name then
        -- \, \; \: \! \\ \{ \} \_ \$ \% \& \# and \<space>
        local ch = s:sub(i + 1, i + 1)
        local spaces = { [','] = ' ', [';'] = ' ', [':'] = ' ', [' '] = ' ', ['!'] = '', ['\\'] = ' ' }
        out[#out + 1] = spaces[ch] or ch
        i = i + 2
      else
        i = i + 1 + #name
        if symbols[name] then
          out[#out + 1] = symbols[name]
        elseif name == 'frac' or name == 'dfrac' or name == 'tfrac' or name == 'cfrac' then
          local num, den
          num, i = argument(s, i)
          den, i = argument(s, i)
          out[#out + 1] = operand(convert(num)) .. '/' .. operand(convert(den))
        elseif name == 'sqrt' then
          local index
          if s:sub(i, i) == '[' then
            local close = s:find(']', i, true) or #s
            index = s:sub(i + 1, close - 1)
            i = close + 1
          end
          local arg
          arg, i = argument(s, i)
          local root = index == '3' and '∛' or index == '4' and '∜' or (index and (script(index, superscript) or '') .. '√') or '√'
          out[#out + 1] = root .. operand(convert(arg))
        elseif name == 'mathbb' then
          local arg
          arg, i = argument(s, i)
          out[#out + 1] = script(arg, blackboard) or convert(arg)
        elseif accents[name] then
          local arg
          arg, i = argument(s, i)
          local inner = convert(arg)
          out[#out + 1] = vim.fn.strchars(inner) == 1 and inner .. accents[name] or inner
        elseif passthrough[name] then
          local arg
          arg, i = argument(s, i)
          out[#out + 1] = (name:match('^text') or name == 'mbox') and arg or convert(arg)
        elseif sizing[name] then
          -- Dropped; the delimiter that follows stays.
          if s:sub(i, i) == '.' then
            i = i + 1
          end
        else
          -- Unknown: keep it as written, argument braces included.
          out[#out + 1] = '\\' .. name
          if s:sub(i, i) == '{' then
            local arg
            arg, i = argument(s, i)
            out[#out + 1] = '{' .. convert(arg) .. '}'
          end
        end
      end
    elseif c == '^' or c == '_' then
      local arg
      arg, i = argument(s, i + 1)
      local inner = convert(arg)
      local mapped = script(inner, c == '^' and superscript or subscript)
      if mapped then
        out[#out + 1] = mapped
      elseif vim.fn.strchars(inner) == 1 then
        out[#out + 1] = c .. inner
      else
        out[#out + 1] = c .. '(' .. inner .. ')'
      end
    elseif c == '{' then
      local arg
      arg, i = argument(s, i)
      out[#out + 1] = convert(arg)
    elseif c == '}' then
      i = i + 1
    elseif c == '~' then
      out[#out + 1] = ' '
      i = i + 1
    elseif c:match('%s') then
      -- Runs of source whitespace become one space (spacing commands are kept as is).
      local last = out[#out]
      if last and not last:match('%s$') then
        out[#out + 1] = ' '
      end
      i = i + 1
    else
      local len = vim.str_utf_end(s, i) + 1
      out[#out + 1] = s:sub(i, i + len - 1)
      i = i + len
    end
  end
  local result = table.concat(out):gsub('([%(%[]) ', '%1'):gsub(' ([%)%]])', '%1')
  return vim.trim(result)
end

M.convert = convert

return M
