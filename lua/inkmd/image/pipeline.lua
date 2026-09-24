-- Conversion jobs: one per content key, a few at a time, results cached on disk by key.
local png = require('inkmd.image.png')

local M = {}

---@class inkmd.ImageResult
---@field status 'pending'|'ok'|'error'
---@field path? string PNG to display
---@field width? integer
---@field height? integer
---@field message? string

---@type table<string, inkmd.ImageResult>
local results = {}
---@type table<string, fun(result: inkmd.ImageResult)[]>
local waiters = {}
local queue = {} ---@type {key: string, start: fun(done: fun(result: inkmd.ImageResult))}[]
local running = 0

M.max_jobs = 2
--- Cache directory; nil means stdpath('cache')/inkmd/img. Tests point it elsewhere.
---@type string?
M.dir = nil

--- Where the PNG for `key` is cached.
function M.cache_path(key)
  local dir = M.dir or vim.fs.joinpath(vim.fn.stdpath('cache'), 'inkmd', 'img')
  vim.fn.mkdir(dir, 'p')
  return vim.fs.joinpath(dir, key .. '.png')
end

--- An ok result for an existing PNG, or nil.
function M.from_png(path)
  local w, h = png.size(path)
  if w then
    return { status = 'ok', path = path, width = w, height = h }
  end
end

local function pump()
  while running < M.max_jobs and #queue > 0 do
    local job = table.remove(queue, 1)
    running = running + 1
    job.start(vim.schedule_wrap(function(result)
      running = running - 1
      results[job.key] = result
      local cbs = waiters[job.key] or {}
      waiters[job.key] = nil
      for _, cb in ipairs(cbs) do
        cb(result)
      end
      pump()
    end))
  end
end

--- Result for `key` if known (finished, failed or running), else nil.
---@return inkmd.ImageResult?
function M.get(key)
  local result = results[key]
  if not result then
    local cached = M.from_png(M.cache_path(key))
    if cached then
      results[key] = cached
      result = cached
    end
  end
  return result
end

--- Start `start` for `key` unless it already ran or is running; `on_done` is called when a
--- job that wasn't finished yet completes.
---@param key string
---@param start fun(done: fun(result: inkmd.ImageResult))
---@param on_done? fun(result: inkmd.ImageResult)
---@return inkmd.ImageResult
function M.request(key, start, on_done)
  local result = M.get(key)
  if result and result.status ~= 'pending' then
    return result
  end
  if on_done then
    waiters[key] = waiters[key] or {}
    table.insert(waiters[key], on_done)
  end
  if not result then
    result = { status = 'pending' }
    results[key] = result
    queue[#queue + 1] = { key = key, start = start }
    pump()
  end
  return results[key]
end

--- Forget results (not the disk cache) so everything is converted or read again.
function M.reset()
  results, waiters, queue = {}, {}, {}
end

--- Run a command; on success the result is the PNG at `out`.
---@param argv string[]
---@param out string
---@param timeout integer ms
---@param parse_error fun(output: string): string
---@param done fun(result: inkmd.ImageResult)
function M.run(argv, out, timeout, parse_error, done)
  if vim.fn.executable(argv[1]) == 0 then
    return done({ status = 'error', message = argv[1] .. ' not found' })
  end
  local tmp = out .. '.part.png'
  local cmd = vim.deepcopy(argv)
  for i, a in ipairs(cmd) do
    if a == '{out}' then
      cmd[i] = tmp
    end
  end
  local ok, err = pcall(vim.system, cmd, { text = true, timeout = timeout }, function(res)
    local result
    if res.code == 0 and png.size(tmp) then
      os.rename(tmp, out)
      result = M.from_png(out)
    end
    if not result then
      os.remove(tmp)
      local output = (res.stderr or '') .. '\n' .. (res.stdout or '')
      if res.signal == 15 or res.code == 124 then
        output = 'timed out after ' .. timeout .. ' ms'
      end
      result = { status = 'error', message = parse_error(output) }
    end
    done(result)
  end)
  if not ok then
    done({ status = 'error', message = tostring(err) })
  end
end

return M
