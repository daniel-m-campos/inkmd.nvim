-- Kitty graphics spike for inkmd.nvim.
--
-- Run it inside the terminal you actually use (a herdr pane in Ghostty):
--   nvim --clean -c 'luafile spike/kitty_spike.lua'
--
-- It needs a real TUI, so `nvim -l` or --headless won't work. It draws the same test
-- image three ways (t=d, t=f, t=t) with Unicode placeholders and puts one inside a
-- concealed fake mermaid block. Everything it learns is written to spike/report.txt.

local here = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h')
local report_path = here .. '/report.txt'
local diacritics = dofile(here .. '/../lua/inkmd/image/diacritics.lua')

vim.o.termguicolors = true

local log_lines = {}

local function escape(s)
  return (s:gsub('[%c]', function(c)
    return c == '\027' and '\\e' or string.format('\\x%02x', c:byte())
  end))
end

local function log(msg)
  local line = os.date('%H:%M:%S ') .. msg
  table.insert(log_lines, line)
  local f = io.open(report_path, 'w')
  if f then
    f:write(table.concat(log_lines, '\n'), '\n')
    f:close()
  end
end

local function send(data)
  vim.api.nvim_ui_send(data)
end

local function apc(control, payload)
  return '\027_G' .. control .. (payload and (';' .. payload) or '') .. '\027\\'
end

-- Terminal replies ------------------------------------------------------------------

local seen_ok, seen_da1 = false, false
vim.api.nvim_create_autocmd('TermResponse', {
  callback = function(ev)
    local seq = ev.data.sequence
    log('TermResponse ' .. escape(seq))
    if seq:match('^\027_Gi=16777001;OK') then
      seen_ok = true
      log('probe: kitty graphics query answered OK' .. (seen_da1 and ' (after DA1!)' or ' (before DA1)'))
    elseif seq:match('^\027%[%?') then
      seen_da1 = true
    end
  end,
})

-- Environment report ----------------------------------------------------------------

local ffi = require('ffi')
pcall(ffi.cdef, [[
  struct inkmd_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
  int ioctl(int fd, unsigned long request, ...);
  int open(const char *path, int flags);
  int close(int fd);
]])
local TIOCGWINSZ = jit.os == 'OSX' and 0x40087468 or 0x5413

local function winsize(fd)
  local ws = ffi.new('struct inkmd_winsize')
  if ffi.C.ioctl(fd, TIOCGWINSZ, ws) ~= 0 then
    return 'ioctl failed'
  end
  return string.format('rows=%d cols=%d xpixel=%d ypixel=%d', ws.ws_row, ws.ws_col, ws.ws_xpixel, ws.ws_ypixel)
end

log('== environment ==')
for _, name in ipairs({ 'TERM', 'TERM_PROGRAM', 'HERDR_ENV', 'HERDR_PANE_ID', 'KITTY_WINDOW_ID', 'GHOSTTY_RESOURCES_DIR', 'TMUX' }) do
  log(string.format('%s=%s', name, os.getenv(name) or ''))
end
log('nvim ' .. tostring(vim.version()) .. ' termguicolors=' .. tostring(vim.o.termguicolors))
for _, fd in ipairs({ 0, 1, 2 }) do
  log(string.format('winsize fd %d: %s', fd, winsize(fd)))
end
local tty = ffi.C.open('/dev/tty', 2)
if tty >= 0 then
  log('winsize /dev/tty: ' .. winsize(tty))
  ffi.C.close(tty)
else
  log('winsize /dev/tty: open failed')
end

-- Test image ------------------------------------------------------------------------

local png_path = here .. '/test.png'
local svg = [[
<svg xmlns="http://www.w3.org/2000/svg" width="400" height="200">
  <rect x="0" y="0" width="200" height="100" fill="#e74c3c"/>
  <rect x="200" y="0" width="200" height="100" fill="#2ecc71"/>
  <rect x="0" y="100" width="200" height="100" fill="#3498db"/>
  <rect x="200" y="100" width="200" height="100" fill="#f1c40f"/>
  <rect x="0.5" y="0.5" width="399" height="199" fill="none" stroke="#ffffff" stroke-width="1"/>
  <g font-family="Helvetica" font-size="40" font-weight="bold" fill="#ffffff" text-anchor="middle">
    <text x="100" y="65">TL</text><text x="300" y="65">TR</text>
    <text x="100" y="165">BL</text><text x="300" y="165">BR</text>
  </g>
</svg>]]
local svg_path = here .. '/test.svg'
local f = assert(io.open(svg_path, 'w'))
f:write(svg)
f:close()
local conv = vim.system({ 'rsvg-convert', '-w', '400', '-h', '200', '-o', png_path, svg_path }):wait()
os.remove(svg_path)
if conv.code ~= 0 then
  log('rsvg-convert failed: ' .. (conv.stderr or ''))
  error('rsvg-convert failed, see ' .. report_path)
end
local png = assert(io.open(png_path, 'rb')):read('*a')
log(string.format('test.png: %d bytes', #png))

-- Placeholders ----------------------------------------------------------------------

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

local function placeholder_rows(id, cols, rows)
  local group = 'SpikeImg' .. id
  vim.api.nvim_set_hl(0, group, { fg = string.format('#%06x', id) })
  local out = {}
  for r = 0, rows - 1 do
    local cells = {}
    for c = 0, cols - 1 do
      cells[#cells + 1] = PLACEHOLDER .. vim.fn.nr2char(diacritics[r + 1]) .. vim.fn.nr2char(diacritics[c + 1])
    end
    out[#out + 1] = { { '  ', 'Normal' }, { table.concat(cells), group } }
  end
  return out
end

local function place(id, cols, rows)
  send(apc(string.format('a=p,U=1,i=%d,c=%d,r=%d,C=1,q=1', id, cols, rows)))
end

-- Transmission methods --------------------------------------------------------------

local IDS = { direct = 0x42A001, file = 0x42A002, temp = 0x42A003 }

local function transmit_direct(id)
  local b64 = vim.base64.encode(png)
  local chunks = {}
  for i = 1, #b64, 4096 do
    chunks[#chunks + 1] = b64:sub(i, i + 4095)
  end
  local out = {}
  for i, chunk in ipairs(chunks) do
    local more = i < #chunks and 1 or 0
    if i == 1 then
      out[#out + 1] = apc(string.format('a=t,f=100,t=d,i=%d,q=1,m=%d', id, more), chunk)
    else
      out[#out + 1] = apc(string.format('m=%d', more), chunk)
    end
  end
  send(table.concat(out))
  log(string.format('sent direct (t=d) id=%d in %d chunks', id, #chunks))
end

local function transmit_file(id)
  send(apc(string.format('a=t,f=100,t=f,i=%d,q=1', id), vim.base64.encode(png_path)))
  log(string.format('sent file (t=f) id=%d', id))
end

local function transmit_temp(id)
  local tmp = vim.fs.joinpath(os.getenv('TMPDIR') or '/tmp', 'tty-graphics-protocol-inkmd-spike.png')
  local out = assert(io.open(tmp, 'wb'))
  out:write(png)
  out:close()
  send(apc(string.format('a=t,f=100,t=t,i=%d,q=1', id), vim.base64.encode(tmp)))
  log(string.format('sent temp (t=t) id=%d path=%s', id, tmp))
end

-- Buffer layout ---------------------------------------------------------------------

local buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(buf, 'inkmd://spike')
vim.api.nvim_set_current_buf(buf)
vim.wo.conceallevel = 2
vim.wo.concealcursor = ''
vim.wo.wrap = false

local lines = {
  'inkmd kitty spike. Report: ' .. report_path,
  'Each section should show a 4-colour grid: TL red, TR green, BL blue, BR yellow.',
  '',
  '== A direct (t=d) ==',
  '',
  '== B file (t=f) ==',
  '',
  '== C temp (t=t) ==',
  '',
  '== conceal test: the fence below hides 4 lines, image A appears above the closing fence ==',
  '```mermaid',
  'graph TD',
  '  A-->B',
  '  B-->C',
  '```',
  '',
  'Commands: :SpikeResize  :SpikeClean  :SpikeRetransmit  :SpikeNote <text>',
  '',
}
for i = 1, 60 do
  lines[#lines + 1] = string.format('filler line %d (scroll with <C-e>/<C-y> and watch the images)', i)
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

local ns = vim.api.nvim_create_namespace('inkmd_spike')
local marks = {}

local function show(key, row, id, cols, rows, above)
  marks[key] = vim.api.nvim_buf_set_extmark(buf, ns, row, 0, {
    id = marks[key],
    virt_lines = placeholder_rows(id, cols, rows),
    virt_lines_above = above or false,
  })
end

-- Send the probe, then all three images.
log('== probe ==')
send('\027[>0q' .. apc('i=16777001,s=1,v=1,a=q,t=d,f=24', 'AAAA') .. '\027[c')

vim.defer_fn(function()
  if not seen_ok then
    log('probe: no OK reply within 500 ms (seen DA1: ' .. tostring(seen_da1) .. ')')
  end
  log('== transmit ==')
  transmit_direct(IDS.direct)
  transmit_file(IDS.file)
  transmit_temp(IDS.temp)
  for _, id in pairs(IDS) do
    place(id, 20, 5)
  end
  show('A', 3, IDS.direct, 20, 5)
  show('B', 5, IDS.file, 20, 5)
  show('C', 7, IDS.temp, 20, 5)
  -- Conceal the opening fence and body (rows 10..13); hang image A above the closing fence (row 14).
  -- conceal_lines hides every row the range touches, so end on row 13, not (14, 0).
  vim.api.nvim_buf_set_extmark(buf, ns, 10, 0, { end_row = 13, conceal_lines = '' })
  show('conceal', 14, IDS.direct, 20, 5, true)
  log('placed all images at 20x5 cells')
end, 500)

-- Commands --------------------------------------------------------------------------

vim.api.nvim_create_user_command('SpikeResize', function()
  place(IDS.direct, 40, 10)
  show('A', 3, IDS.direct, 40, 10)
  log('resized A to 40x10')
end, {})

vim.api.nvim_create_user_command('SpikeClean', function()
  for _, id in pairs(IDS) do
    send(apc(string.format('a=d,d=I,i=%d,q=1', id)))
  end
  log('deleted all three images (d=I)')
end, {})

vim.api.nvim_create_user_command('SpikeRetransmit', function()
  place(IDS.direct, 20, 5)
  log('re-placed A without re-sending data; expect ENOENT if it was deleted')
end, {})

vim.api.nvim_create_user_command('SpikeNote', function(o)
  log('NOTE: ' .. o.args)
end, { nargs = '+' })
