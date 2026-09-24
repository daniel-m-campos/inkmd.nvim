local h = require('helpers')
local config = require('inkmd.config')
local kitty = require('inkmd.image.kitty')
local pipeline = require('inkmd.image.pipeline')

local PLACEHOLDER = vim.fn.nr2char(0x10EEEE)

--- Run `fn` with images forced on, a fake mmdc, a fresh cache and captured terminal output.
local function with_images(fn)
  local opts = config.options.image
  local saved = vim.deepcopy(opts)
  local write = kitty.write
  local sent = {}
  opts.backend = 'kitty'
  opts.mermaid.cmd = h.root .. '/tests/fixtures/fake-mmdc'
  opts.mermaid.debounce = 50
  pipeline.dir = h.root .. '/tests/.tmp/cache'
  vim.fn.delete(pipeline.dir, 'rf')
  pipeline.reset()
  kitty.write = function(data)
    sent[#sent + 1] = data
  end
  local ok, err = pcall(fn, sent)
  kitty.clear()
  kitty.write = write
  config.options.image = saved
  pipeline.dir = nil
  pipeline.reset()
  assert(ok, err)
end

--- Text of every virtual line in the buffer, in order.
local function virt_lines(buf)
  local out = {}
  -- All namespaces: a live preview is in the raw block's own (window-scoped) namespace.
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
    for _, line in ipairs(m[4].virt_lines or {}) do
      local parts = {}
      for _, chunk in ipairs(line) do
        parts[#parts + 1] = chunk[1]
      end
      out[#out + 1] = table.concat(parts)
    end
  end
  return out
end

local function has_image(buf)
  for _, line in ipairs(virt_lines(buf)) do
    if line:find(PLACEHOLDER, 1, true) then
      return true
    end
  end
  return false
end

local function move(row)
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  vim.api.nvim_exec_autocmds('CursorMoved', { buffer = 0 })
end

describe('image units', function()
  it('reads the PNG size from its header', function()
    local w, ht = require('inkmd.image.png').size(h.root .. '/tests/fixtures/img/red.png')
    h.eq({ w, ht }, { 64, 32 })
    h.eq(require('inkmd.image.png').size(h.root .. '/tests/fixtures/img/red.svg'), nil)
  end)

  it('encodes placeholder rows and columns with diacritics', function()
    local rows = require('inkmd.image.placeholder').rows(2, 2)
    local d = require('inkmd.image.diacritics')
    local cell = function(r, c)
      return PLACEHOLDER .. vim.fn.nr2char(d[r]) .. vim.fn.nr2char(d[c])
    end
    h.eq(rows, { cell(1, 1) .. cell(1, 2), cell(2, 1) .. cell(2, 2) })
  end)

  it('puts the image id in the placeholder foreground', function()
    local group = require('inkmd.image.placeholder').hl(0x42a001)
    h.eq(vim.api.nvim_get_hl(0, { name = group }).fg, 0x42a001)
  end)

  it('fits pictures into the cell box keeping the aspect ratio', function()
    local fit = require('inkmd.image.fit').cells
    local cell = { width = 8, height = 16 }
    h.eq({ fit(64, 32, cell, 80, 30) }, { 8, 2 })
    h.eq({ fit(1600, 800, cell, 50, 30) }, { 50, 13 })
    -- Too tall: rows capped, columns shrink with them.
    h.eq({ fit(800, 1600, cell, 80, 10) }, { 10, 10 })
  end)

  it('sends images in 4096-byte chunks and places them virtually', function()
    with_images(function(sent)
      local big = h.root .. '/tests/.tmp/big.png'
      vim.fn.mkdir(h.root .. '/tests/.tmp', 'p')
      -- A valid header followed by padding is enough for the transport.
      local f = assert(io.open(h.root .. '/tests/fixtures/img/red.png', 'rb'))
      local data = f:read('*a') .. string.rep('\0', 9000)
      f:close()
      f = assert(io.open(big, 'wb'))
      f:write(data)
      f:close()
      local id = kitty.image(big, 10, 3)
      vim.wait(1000, function()
        return kitty.pending() == 0
      end)
      local encoded = vim.base64.encode(data)
      h.eq(#sent, math.ceil(#encoded / 4096) + 1)
      h.truthy(sent[1]:find('^\27_Ga=t,f=100,t=d,i=' .. id .. ',q=1,m=1;'), sent[1]:sub(1, 40))
      h.truthy(sent[#sent - 1]:find('^\27_Gm=0,q=1;'), 'last chunk ends the transfer')
      h.eq(sent[#sent], '\27_Ga=p,U=1,i=' .. id .. ',c=10,r=3,C=1,q=1\27\\')
      h.eq(kitty.image(big, 10, 3), id)
      h.truthy(kitty.image(big, 5, 2) ~= id, 'another size gets another id')
    end)
  end)

  it('keeps the message of mmdc errors and drops colours and the stack', function()
    local msg = require('inkmd.image.convert.mermaid').parse_error(
      'Generating single mermaid chart\n\27[31mError: Parse error on line 3:\27[39m\n\27[31m...A -->\27[39m\n'
        .. '\27[31mParser.parseError (x.mjs:1:2)\27[39m\n    at y (z.js:1:1)\n'
    )
    h.eq(msg, 'Error: Parse error on line 3:\n...A -->')
  end)

  it('keys diagrams by source and theme, not by window', function()
    local mermaid = require('inkmd.image.convert.mermaid')
    local opts = config.options.image.mermaid
    h.eq(mermaid.key('A --> B', opts), mermaid.key('A --> B', opts))
    h.truthy(mermaid.key('A --> B', opts) ~= mermaid.key('A --> C', opts), 'source changes the key')
  end)

  it('pads pictures to the exact shape of their cell box', function()
    with_images(function()
      local pad = require('inkmd.image.pad')
      local png = require('inkmd.image.png')
      local cell = { width = 8, height = 16 }
      local exact = pipeline.from_png(h.root .. '/tests/fixtures/img/red.png')
      h.eq(pad.needed(exact, 8, 2, cell), false)
      -- 64x40 px is 8 columns by 2.5 rows: it gets 3 rows (48 px) and must not be stretched.
      local tall = pipeline.from_png(h.root .. '/tests/fixtures/img/green-64x40.png')
      local cols, rows = require('inkmd.image.fit').cells(tall.width, tall.height, cell, 80, 30)
      h.eq({ cols, rows }, { 8, 3 })
      h.eq(pad.needed(tall, cols, rows, cell), true)
      local key = pad.key(tall, cols, rows, cell)
      local result
      pipeline.request(key, pad.job(tall, key, cols, rows, cell), function(r)
        result = r
      end)
      h.truthy(vim.wait(5000, function()
        return result ~= nil
      end, 20), 'padded')
      h.eq(result.status, 'ok', result.message)
      h.eq({ png.size(result.path) }, { 64, 48 })
    end)
  end)

  it('sends the padded picture once it is ready', function()
    with_images(function(sent)
      vim.cmd.cd(h.root)
      local buf = h.scratch({ '![g](tests/fixtures/img/green-64x40.png)', '', 'end' }, { 3, 0 })
      h.truthy(vim.wait(5000, function()
        -- Transfers of a 64x48 PNG: its IHDR (base64 of the header) is in the first chunk.
        for _, data in ipairs(sent) do
          local payload = data:match(';(.*)\27\\$')
          if payload and data:find('a=t', 1, true) then
            local bytes = vim.base64.decode(payload:sub(1, 32))
            if #bytes >= 24 and bytes:byte(24) == 48 and bytes:byte(20) == 64 then
              return true
            end
          end
        end
      end, 20), 'padded 64x48 picture sent')
      h.truthy(buf > 0, 'buffer')
    end)
  end)

  it('falls back to text when no UI is attached', function()
    h.eq(require('inkmd.image.detect').unavailable('auto'), 'no UI attached')
    h.eq(require('inkmd.image.detect').unavailable('kitty'), nil)
  end)
end)

describe('image rendering', function()
  it('shows a pending line, then replaces the mermaid block with the picture', function()
    with_images(function(sent)
      local buf = h.scratch({ 'before', '```mermaid', 'A --> B', '```', 'after' }, { 1, 0 })
      h.truthy(vim.tbl_contains(virt_lines(buf), '⋯ rendering mermaid…'), 'pending line')
      h.truthy(vim.wait(5000, function()
        return has_image(buf)
      end, 20), 'picture drawn')
      h.eq(h.screen()[1], 'before')
      h.eq(h.screen()[#h.screen()], 'after')
      h.truthy(not vim.tbl_contains(h.screen(), 'A --> B'), 'source hidden')
      h.truthy(table.concat(sent):find('a=p,U=1', 1, true), 'placed')
    end)
  end)

  it('keeps the picture below the source while the block is edited', function()
    with_images(function()
      local buf = h.scratch({ 'before', '```mermaid', 'A --> B', '```', 'after' }, { 1, 0 })
      vim.wait(5000, function()
        return has_image(buf)
      end, 20)
      move(3)
      h.truthy(vim.tbl_contains(h.screen(), 'A --> B'), 'source shown')
      h.truthy(has_image(buf), 'picture kept')
      -- Edit: the old picture stays up while the new one renders after the debounce.
      vim.api.nvim_buf_set_lines(buf, 2, 3, false, { 'A --> C' })
      require('inkmd').render_now(buf)
      h.truthy(has_image(buf), 'previous picture shown while re-rendering')
    end)
  end)

  it('shows mermaid errors under the source', function()
    with_images(function()
      local buf = h.scratch({ 'before', '```mermaid', 'A --> error', '```', 'after' }, { 1, 0 })
      h.truthy(vim.wait(5000, function()
        return vim.tbl_contains(virt_lines(buf), 'Error: Parse error on line 2:')
      end, 20), 'error shown: ' .. vim.inspect(virt_lines(buf)))
      local lines = virt_lines(buf)
      h.eq(#lines, 3)
      h.truthy(h.screen()[2]:find('mermaid', 1, true), 'source still drawn as code')
    end)
  end)

  it('draws local images below their paragraph and keeps alt text for missing ones', function()
    with_images(function()
      -- Relative to the working directory for an unnamed buffer (a long absolute path would
      -- wrap the line: hidden text still counts for wrapping).
      vim.cmd.cd(h.root)
      local buf = h.scratch({ '![red](tests/fixtures/img/red.png) and ![gone](nope.png)', '', 'end' }, { 3, 0 })
      h.truthy(vim.wait(5000, function()
        return has_image(buf)
      end, 20), 'picture drawn')
      h.eq(h.screen()[1], '󰋩 red and 󰋩 gone')
      h.eq(#virt_lines(buf), 2)
    end)
  end)

  it('converts svg images to png', function()
    with_images(function()
      local path = h.root .. '/tests/fixtures/img/red.svg'
      local buf = h.scratch({ '![svg](' .. path .. ')', '', 'end' }, { 3, 0 })
      h.truthy(vim.wait(5000, function()
        return has_image(buf)
      end, 20), 'svg drawn: ' .. vim.inspect(virt_lines(buf)))
    end)
  end)
end)
