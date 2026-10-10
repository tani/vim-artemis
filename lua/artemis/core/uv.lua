-- L4: a pragmatic subset of libuv (vim.uv / vim.loop) on top of Vim's
-- timers, jobs and file functions. Synchronous fs calls only; when a callback
-- is passed it is invoked on the next event-loop tick.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F = u.F

local M = {}

local function errtuple(code, msg, extra)
  return nil, code .. ': ' .. msg .. (extra and (': ' .. extra) or ''), code
end

--- Complete a "maybe async" libuv call.
local function finish(cb, err, ...)
  if type(cb) == 'function' then
    local args = { ... }
    local n = select('#', ...)
    F.timer_start(0, function()
      local unpack = unpack or table.unpack
      cb(err, unpack(args, 1, n))
    end)
    return {}
  end
  if err then
    return nil, err
  end
  return ...
end

------------------------------------------------------------------- time
function M.now()
  return math.floor(F.reltimefloat(F.reltime()) * 1000)
end
function M.update_time() end
function M.hrtime()
  return math.floor(F.reltimefloat(F.reltime()) * 1e9)
end

------------------------------------------------------------------ timers
local Timer = {}
Timer.__index = Timer

function M.new_timer()
  return setmetatable({ _id = nil, _active = false, _closed = false, _repeat = 0 }, Timer)
end

function Timer:start(timeout, rep, cb)
  self:stop()
  self._repeat = rep or 0
  self._cb = cb
  self._active = true
  self._due = M.now() + timeout
  local function fire()
    if self._closed or not self._active then
      return
    end
    if self._repeat > 0 then
      self._due = M.now() + self._repeat
      self._id = F.timer_start(self._repeat, fire)
    else
      self._active = false
    end
    self._cb()
  end
  self._id = F.timer_start(timeout, fire)
  return 0
end

function Timer:stop()
  if self._id then
    F.timer_stop(self._id)
    self._id = nil
  end
  self._active = false
  return 0
end

function Timer:again()
  if self._cb then
    return self:start(self._repeat, self._repeat, self._cb)
  end
end

function Timer:set_repeat(r)
  self._repeat = r
end
function Timer:get_repeat()
  return self._repeat
end
function Timer:is_active()
  return self._active
end
function Timer:get_due_in()
  return self._active and math.max(0, self._due - M.now()) or 0
end
function Timer:close()
  self:stop()
  self._closed = true
end
function Timer:is_closing()
  return self._closed
end
function Timer:unref() end
function Timer:ref() end
function Timer:has_ref()
  return true
end

local Async = {}
Async.__index = Async
function M.new_async(cb)
  return setmetatable({ _cb = cb, _closed = false }, Async)
end
function Async:send(...)
  local args = { ... }
  local n = select('#', ...)
  F.timer_start(0, function()
    if not self._closed then
      local unpack = unpack or table.unpack
      self._cb(unpack(args, 1, n))
    end
  end)
  return 0
end
function Async:close()
  self._closed = true
end
function Async:is_closing()
  return self._closed
end

-------------------------------------------------------------- file system
local function stat_of(path)
  local t = F.getftype(path)
  if t == '' then
    return nil
  end
  local type_map = { dir = 'directory', file = 'file', link = 'link', fifo = 'fifo', socket = 'socket', cdev = 'char', bdev = 'block' }
  local mtime = F.getftime(path)
  return {
    type = type_map[t] or 'file',
    size = math.max(F.getfsize(path), 0),
    mode = 0,
    mtime = { sec = mtime, nsec = 0 },
    atime = { sec = mtime, nsec = 0 },
    ctime = { sec = mtime, nsec = 0 },
    birthtime = { sec = mtime, nsec = 0 },
  }
end

function M.fs_stat(path, cb)
  local s = stat_of(path)
  if not s then
    return finish(cb, 'ENOENT: no such file or directory: ' .. path)
  end
  return finish(cb, nil, s)
end
M.fs_lstat = M.fs_stat

function M.fs_access(path, mode, cb)
  local ok = F.getftype(path) ~= ''
  return finish(cb, nil, ok)
end

function M.fs_realpath(path, cb)
  if F.getftype(path) == '' then
    return finish(cb, 'ENOENT: no such file or directory: ' .. path)
  end
  return finish(cb, nil, F.resolve(F.fnamemodify(path, ':p')):gsub('/$', ''))
end

function M.cwd()
  return F.getcwd()
end
function M.chdir(dir)
  host.exec('cd ' .. F.fnameescape(dir))
  return 0
end
function M.os_getenv(name)
  return os.getenv(name)
end
function M.os_setenv(name, value)
  F.setenv(name, value)
  return true
end
function M.os_homedir()
  return os.getenv('HOME')
end
function M.os_tmpdir()
  return os.getenv('TMPDIR') or '/tmp'
end
local uname
function M.os_uname()
  if not uname then
    local ok, out = pcall(F.system, 'uname -srvm')
    local s, r, v, m = tostring(out):match('^(%S+)%s+(%S+)%s+(.-)%s+(%S+)%s*$')
    uname = { sysname = s or 'Unknown', release = r or '', version = v or '', machine = m or '' }
  end
  return uname
end
function M.os_getpid()
  return tonumber(F.getpid and 0 or 0)
end
function M.available_parallelism()
  return 1
end

function M.fs_scandir(path, cb)
  if F.isdirectory(path) == 0 then
    return finish(cb, 'ENOENT: no such file or directory: ' .. path)
  end
  local entries = F.readdir(path)
  local h = { _entries = entries, _i = 0, _path = path }
  return finish(cb, nil, h)
end
function M.fs_scandir_next(h)
  h._i = h._i + 1
  local name = h._entries[h._i]
  if not name then
    return nil
  end
  local t = F.getftype(h._path .. '/' .. name)
  return name, t == 'dir' and 'directory' or t == 'link' and 'link' or 'file'
end

function M.fs_mkdir(path, mode, cb)
  F.mkdir(path)
  return finish(cb, nil, true)
end
function M.fs_unlink(path, cb)
  local rc = F.delete(path)
  if rc ~= 0 then
    return finish(cb, 'ENOENT: no such file or directory: ' .. path)
  end
  return finish(cb, nil, true)
end
function M.fs_rename(a, b, cb)
  local rc = F.rename(a, b)
  if rc ~= 0 then
    return finish(cb, 'ENOENT: no such file or directory: ' .. a)
  end
  return finish(cb, nil, true)
end

-- file handles: whole-file buffered
local Fd = {}
function M.fs_open(path, flags, mode, cb)
  if type(mode) == 'function' then
    cb, mode = mode, nil
  end
  local f, err = io.open(path, (flags == 'r' or flags == 'rb') and 'rb' or flags:find('a') and 'ab' or 'wb')
  if not f then
    return finish(cb, 'ENOENT: no such file or directory: ' .. path)
  end
  return finish(cb, nil, { _f = f })
end
function M.fs_read(fd, size, offset, cb)
  if type(offset) == 'function' then
    cb, offset = offset, nil
  end
  if offset and offset >= 0 then
    fd._f:seek('set', offset)
  end
  local data = fd._f:read(size) or ''
  return finish(cb, nil, data)
end
function M.fs_write(fd, data, offset, cb)
  if type(offset) == 'function' then
    cb, offset = offset, nil
  end
  if offset and offset >= 0 then
    fd._f:seek('set', offset)
  end
  fd._f:write(data)
  return finish(cb, nil, #data)
end
function M.fs_close(fd, cb)
  fd._f:close()
  return finish(cb, nil, true)
end
function M.fs_fstat(fd, cb)
  local cur = fd._f:seek('cur')
  local size = fd._f:seek('end')
  fd._f:seek('set', cur)
  return finish(cb, nil, { type = 'file', size = size })
end

-- Features we cannot offer fail loudly instead of silently.
for _, name in ipairs({ 'new_pipe', 'new_tcp', 'new_udp', 'new_fs_event', 'new_fs_poll', 'new_signal', 'new_tty' }) do
  M[name] = function()
    error('artemis: vim.uv.' .. name .. ' is not supported on Vim', 2)
  end
end
-- check / idle / prepare run once per loop iteration in libuv; approximate
-- with a 10 ms repeating timer.
local function loop_handle()
  local h = { _closed = false }
  function h:start(cb)
    self:stop()
    self._cb = cb
    self._id = F.timer_start(10, function()
      if not self._closed and self._cb then
        self._cb()
      end
    end, { ['repeat'] = -1 })
    return 0
  end
  function h:stop()
    if self._id then
      F.timer_stop(self._id)
      self._id = nil
    end
    return 0
  end
  function h:close()
    self:stop()
    self._closed = true
  end
  function h:is_closing()
    return self._closed
  end
  function h:is_active()
    return self._id ~= nil
  end
  return h
end
M.new_idle = loop_handle
M.new_check = loop_handle
M.new_prepare = loop_handle

function M.run() end
function M.stop() end
function M.loop_alive()
  return false
end

return M
