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
  local fh = io.open('/proc/self/stat', 'r')
  if fh then
    local pid = fh:read('*l'):match('^(%d+)')
    fh:close()
    return tonumber(pid)
  end
  return 0
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


--------------------------------------------------------- pipes and spawn
local Pipe = {}
Pipe.__index = Pipe

function M.new_pipe(ipc)
  return setmetatable({ _queue = {}, _eof = false, _closed = false }, Pipe)
end

local function deliver(pipe)
  while pipe._cb and #pipe._queue > 0 do
    local chunk = table.remove(pipe._queue, 1)
    if chunk == false then
      pipe._cb(nil, nil)
    else
      pipe._cb(nil, chunk)
    end
  end
end

function Pipe:read_start(cb)
  self._cb = cb
  deliver(self)
  return 0
end
function Pipe:read_stop()
  self._cb = nil
  return 0
end
function Pipe:write(data, cb)
  if not self._chan then
    return nil, 'EPIPE: broken pipe', 'EPIPE'
  end
  if type(data) == 'table' then
    data = table.concat(data)
  end
  F.ArtemisChanSend(self._chan, data)
  if cb then
    F.timer_start(0, function() cb(nil) end)
  end
  return {}
end
function Pipe:shutdown(cb)
  if self._chan then
    pcall(F.ArtemisChanCloseIn, self._chan)
  end
  if cb then
    F.timer_start(0, function() cb(nil) end)
  end
  return {}
end
function Pipe:close()
  if self._chan and not self._closed then
    -- closing a child's stdin pipe signals EOF to it
    pcall(F.ArtemisChanCloseIn, self._chan)
  end
  self._closed = true
  self._cb = nil
end
function Pipe:is_closing()
  return self._closed
end
function Pipe:is_readable()
  return not self._eof
end
function Pipe:is_writable()
  return self._chan ~= nil
end
function Pipe:unref() end
function Pipe:ref() end

local Process = {}
Process.__index = Process
function Process:kill(sig)
  return M.process_kill(self, sig)
end
function Process:close()
  self._closed = true
end
function Process:is_closing()
  return self._closed
end
function Process:get_pid()
  return self.pid
end
function Process:ref() end
function Process:unref() end

local signals = { [1] = 'hup', [2] = 'int', [3] = 'quit', [9] = 'kill', [15] = 'term' }
local function signame(sig)
  if type(sig) == 'number' then
    return signals[sig] or 'term'
  end
  sig = tostring(sig or 'sigterm'):lower():gsub('^sig', '')
  return sig
end

function M.process_kill(proc, sig)
  if proc._job then
    F.ArtemisJobStop(proc._job, signame(sig))
  end
  return 0
end

function M.kill(pid, sig)
  local name = signame(sig)
  F.system({ 'kill', '-' .. (name == 'term' and 'TERM' or name:upper()), tostring(pid) })
  return 0
end

function M.spawn(path, opts, on_exit)
  opts = opts or {}
  local cmd = { path }
  for _, a in ipairs(opts.args or {}) do
    cmd[#cmd + 1] = a
  end
  local stdio = opts.stdio or {}
  local pin, pout, perr = stdio[1], stdio[2], stdio[3]
  local proc = setmetatable({ _closed = false }, Process)
  local closed, exited = 0, nil
  local function maybe_exit()
    if exited ~= nil and closed >= 2 and not proc._exit_called then
      proc._exit_called = true
      if on_exit then
        on_exit(exited, 0)
      end
    end
  end
  local function feeder(pipe)
    return function(_, msg)
      if pipe and type(pipe) == 'table' then
        pipe._queue[#pipe._queue + 1] = msg
        deliver(pipe)
      end
    end
  end
  local vopts = {
    mode = 'raw',
    in_io = pin and 'pipe' or 'null',
    out_io = pout and 'pipe' or 'null',
    err_io = perr and 'pipe' or 'null',
    out_cb = feeder(pout),
    err_cb = feeder(perr),
    exit_cb = function(_, code)
      exited = code
      maybe_exit()
    end,
    close_cb = function()
      for _, p in ipairs({ pout, perr }) do
        if p then
          p._eof = true
          p._queue[#p._queue + 1] = false
          deliver(p)
        end
      end
      closed = 2
      maybe_exit()
    end,
  }
  if opts.cwd then
    vopts.cwd = opts.cwd
  end
  if opts.env then
    local env = {}
    for _, kv in ipairs(opts.env) do
      local k, v = kv:match('^([^=]*)=(.*)$')
      if k then
        env[k] = v
      end
    end
    vopts.env = env
  end
  local job = F.ArtemisJobStart(cmd, vopts)
  if F.ArtemisJobStatus(job) == 'fail' then
    return nil, 'ENOENT: no such file or directory: ' .. path, 'ENOENT'
  end
  proc._job = job
  proc.pid = F.ArtemisJobInfo(job).process
  local chan = job
  if pin then
    pin._chan = chan
  end
  return proc, proc.pid
end

-- Features we cannot offer fail loudly instead of silently.
-- fs_event / fs_poll: emulated by polling mtime/size once per second.
local function poll_handle(kind)
  local h = { _closed = false }
  function h:start(path, a, b)
    local cb = type(a) == 'function' and a or b
    self:stop()
    self._path = path
    local function sig()
      return F.getftime(path) .. ':' .. F.getfsize(path) .. ':' .. F.getftype(path)
    end
    self._sig = sig()
    self._id = F.timer_start(1000, function()
      if self._closed then
        return
      end
      local now = sig()
      if now ~= self._sig then
        self._sig = now
        if kind == 'event' then
          cb(nil, path:match('[^/]+$') or path, { change = true })
        else
          cb(nil, {}, {})
        end
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
  function h:getpath()
    return self._path
  end
  return h
end
function M.new_fs_event()
  return poll_handle('event')
end
function M.new_fs_poll()
  return poll_handle('poll')
end

for _, name in ipairs({ 'new_tcp', 'new_udp', 'new_signal', 'new_tty' }) do
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

-- luv exposes every handle method also as a plain function: uv.close(h),
-- uv.is_active(h), uv.timer_start(t, ...), uv.read_start(pipe, cb), ...
local same = {
  'is_active', 'is_closing', 'close', 'ref', 'unref', 'has_ref', 'read_start', 'read_stop',
  'write', 'shutdown', 'is_readable', 'is_writable',
}
for _, name in ipairs(same) do
  M[name] = M[name] or function(h, ...)
    return h[name](h, ...)
  end
end
local renamed = {
  timer_start = 'start', timer_stop = 'stop', timer_again = 'again', timer_set_repeat = 'set_repeat',
  timer_get_repeat = 'get_repeat', timer_get_due_in = 'get_due_in', async_send = 'send',
  check_start = 'start', check_stop = 'stop', idle_start = 'start', idle_stop = 'stop',
  prepare_start = 'start', prepare_stop = 'stop',
}
for fname, method in pairs(renamed) do
  M[fname] = M[fname] or function(h, ...)
    return h[method](h, ...)
  end
end

function M.run() end
function M.stop() end
function M.loop_alive()
  return false
end

return M
