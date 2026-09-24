-- Kitty graphics protocol transport. Images are sent inline as base64 (t=d): herdr paints
-- file transfers (t=f) blank. Each (picture, size) pair gets its own image id with one
-- virtual placement (U=1) that placeholder cells refer to.
local M = {}

local CHUNK = 4096
local CHUNKS_PER_TICK = 32

--- Output function; tests replace it to capture what would reach the terminal.
---@type fun(data: string)
M.write = function(data)
  vim.api.nvim_ui_send(data)
end

---@param control string
---@param payload? string
local function apc(control, payload)
  return '\027_G' .. control .. (payload and (';' .. payload) or '') .. '\027\\'
end

-- Id space: 24 bits (the placeholder foreground colour), low 16 bits count up, the top byte
-- comes from the process id so two Neovims in one terminal rarely collide.
local base = bit.lshift(bit.band(vim.fn.getpid(), 0x7f) + 1, 16)
local counter = 0

---@class inkmd.KittyImage
---@field id integer
---@field path string
---@field cols integer
---@field rows integer
---@field state 'queued'|'sent'

---@type table<string, inkmd.KittyImage> by path:cols:rows
local images = {}
---@type table<integer, inkmd.KittyImage>
local by_id = {}

local queue = {} ---@type string[] pending writes
local draining = false

local function drain()
  if draining then
    return
  end
  draining = true
  local function step()
    for _ = 1, CHUNKS_PER_TICK do
      local data = table.remove(queue, 1)
      if not data then
        draining = false
        return
      end
      M.write(data)
    end
    vim.schedule(step)
  end
  step()
end

--- Queue the transmission and placement of `image`.
---@param image inkmd.KittyImage
local function send(image)
  local f = io.open(image.path, 'rb')
  if not f then
    return
  end
  local data = vim.base64.encode(f:read('*a'))
  f:close()
  local n = math.ceil(#data / CHUNK)
  for i = 1, n do
    local chunk = data:sub((i - 1) * CHUNK + 1, i * CHUNK)
    local more = i < n and 1 or 0
    if i == 1 then
      queue[#queue + 1] = apc(string.format('a=t,f=100,t=d,i=%d,q=1,m=%d', image.id, more), chunk)
    else
      queue[#queue + 1] = apc(string.format('m=%d,q=1', more), chunk)
    end
  end
  queue[#queue + 1] = apc(string.format('a=p,U=1,i=%d,c=%d,r=%d,C=1,q=1', image.id, image.cols, image.rows))
  image.state = 'sent'
  drain()
end

--- Image id showing the PNG at `path` in a `cols` x `rows` cell box, sending it if needed.
---@return integer
function M.image(path, cols, rows)
  local key = string.format('%s:%d:%d', path, cols, rows)
  local image = images[key]
  if not image then
    counter = (counter % 0xffff) + 1
    image = { id = base + counter, path = path, cols = cols, rows = rows, state = 'queued' }
    images[key] = image
    by_id[image.id] = image
    send(image)
  end
  return image.id
end

--- Send every image again (after the terminal lost them, e.g. a reattach).
function M.resend()
  for _, image in pairs(images) do
    send(image)
  end
end

--- Delete all of our images from the terminal (never d=A: other programs' images stay).
function M.clear()
  for id in pairs(by_id) do
    queue[#queue + 1] = apc(string.format('a=d,d=I,i=%d,q=1', id))
  end
  images, by_id = {}, {}
  -- Flush synchronously: this also runs on exit.
  while #queue > 0 do
    M.write(table.remove(queue, 1))
  end
end

--- A terminal error reply for one of our ids (q=1 still reports errors): the image is gone,
--- so send it again.
---@param sequence string
function M.on_response(sequence)
  local id, msg = sequence:match('^\027_Gi=(%d+)[^;]*;(%u+)')
  local image = id and by_id[tonumber(id)]
  if image and msg == 'ENOENT' then
    send(image)
  end
end

--- Number of queued writes (tests).
function M.pending()
  return #queue
end

return M
