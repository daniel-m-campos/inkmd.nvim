-- Terminal cell size in pixels, from the tty's window size (TIOCGWINSZ). Neovim can't read
-- CSI replies (TermResponse only delivers DA1/OSC/DCS/APC), so this asks the kernel.
local M = {}

local cached

local function query()
  local ok, ffi = pcall(require, 'ffi')
  if not ok then
    return nil
  end
  pcall(ffi.cdef, [[
    struct inkmd_winsize { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel; };
    int ioctl(int fd, unsigned long request, ...);
  ]])
  local TIOCGWINSZ = jit.os == 'OSX' and 0x40087468 or 0x5413
  local ws = ffi.new('struct inkmd_winsize')
  for fd = 0, 2 do
    if ffi.C.ioctl(fd, TIOCGWINSZ, ws) == 0 and ws.ws_xpixel > 0 and ws.ws_col > 0 then
      return { width = ws.ws_xpixel / ws.ws_col, height = ws.ws_ypixel / ws.ws_row }
    end
  end
end

--- Cell width and height in pixels. Falls back to 8x16 (a 2:1 cell) when unknown.
---@return {width: number, height: number}
function M.size()
  cached = cached or query() or { width = 8, height = 16 }
  return cached
end

--- Forget the cached size (font or window size changed).
function M.reset()
  cached = nil
end

return M
