-- Neovim job API (jobstart/jobstop/chansend/jobwait) and vim.system built on
-- Vim's job_start(). Only loaded on Vim.
local u = require('artemis.api.util')
local F = u.F

local M = {}

local jobs = {}
local next_id = 0

local function split_chunk(s)
  return vim.split(s, '\n', { plain = true })
end

local function to_argv(cmd)
  if type(cmd) == 'string' then
    return { vim.o.shell, vim.o.shellcmdflag, cmd }
  end
  return cmd
end

--- jobstart(cmd, opts) with Neovim semantics for on_stdout/on_stderr/on_exit.
function M.jobstart(cmd, opts)
  opts = opts or {}
  next_id = next_id + 1
  local id = next_id
  local job = { id = id, out = {}, err = {}, closed = 0, exited = nil, finished = false }
  jobs[id] = job

  local function deliver(kind, chunk)
    local cb = opts['on_' .. kind]
    local buffered = opts[kind .. '_buffered']
    if buffered then
      local acc = job[kind == 'stdout' and 'out' or 'err']
      if chunk then
        acc[#acc + 1] = chunk
      end
      return
    end
    if cb then
      cb(id, chunk and split_chunk(chunk) or { '' }, kind)
    end
  end

  local function maybe_finish()
    if job.finished or job.exited == nil or job.closed < 2 then
      return
    end
    job.finished = true
    for _, kind in ipairs({ 'stdout', 'stderr' }) do
      if opts[kind .. '_buffered'] and opts['on_' .. kind] then
        local acc = table.concat(job[kind == 'stdout' and 'out' or 'err'])
        opts['on_' .. kind](id, split_chunk(acc), kind)
      elseif opts['on_' .. kind] then
        opts['on_' .. kind](id, { '' }, kind)
      end
    end
    if opts.on_exit then
      opts.on_exit(id, job.exited, 'exit')
    end
  end

  local vopts = {
    mode = 'raw',
    out_io = 'pipe',
    err_io = opts.stderr_buffered ~= nil or opts.on_stderr and 'pipe' or 'pipe',
    out_cb = function(_, msg)
      deliver('stdout', msg)
    end,
    err_cb = function(_, msg)
      deliver('stderr', msg)
    end,
    exit_cb = function(_, code)
      job.exited = code
      maybe_finish()
    end,
    close_cb = function()
      job.closed = 2
      maybe_finish()
    end,
    stoponexit = opts.detach and '' or 'term',
  }
  if opts.cwd then
    vopts.cwd = opts.cwd
  end
  if opts.env then
    vopts.env = opts.env
  end
  if opts.stdin == 'null' then
    vopts.in_io = 'null'
  end
  job.handle = F.ArtemisJobStart(to_argv(cmd), vopts)
  if F.ArtemisJobStatus(job.handle) == 'fail' then
    jobs[id] = nil
    return -1
  end
  job.channel = job.handle
  return id
end

function M.jobstop(id)
  local j = jobs[id]
  if not j then
    return 0
  end
  if j.term then
    F.term_setkill(j.term, 'term')
    pcall(vim.cmd, 'silent! bwipeout! ' .. j.term)
    return 1
  end
  F.ArtemisJobStop(j.handle)
  return 1
end

function M.chansend(id, data)
  local j = jobs[id]
  if not j then
    error('Invalid channel id', 2)
  end
  if type(data) == 'table' then
    data = table.concat(data, '\n')
  end
  if j.term then
    F.term_sendkeys(j.term, data)
  else
    F.ArtemisChanSend(j.channel, data)
  end
  return #data
end

--- termopen(): run `cmd` in a terminal in the current window (Vim terminal).
--- Only on_exit is supported; terminal output is not delivered to callbacks.
function M.termopen(cmd, opts)
  opts = opts or {}
  next_id = next_id + 1
  local id = next_id
  local job = { id = id, closed = 2 }
  jobs[id] = job
  local vopts = { curwin = 1, term_finish = 'open' }
  if opts.cwd then
    vopts.cwd = opts.cwd
  end
  if opts.env then
    vopts.env = opts.env
  end
  vopts.exit_cb = function(_, code)
    job.exited, job.finished = code, true
    if opts.on_exit then
      opts.on_exit(id, code, 'exit')
    end
  end
  local argv = to_argv(cmd)
  job.term = F.term_start(argv, vopts)
  if job.term == 0 then
    jobs[id] = nil
    return -1
  end
  return id
end

function M.chanclose(id, stream)
  local j = jobs[id]
  if j and not j.term and (stream == nil or stream == 'stdin') then
    F.ArtemisChanCloseIn(j.channel)
  end
  return 1
end

function M.jobpid(id)
  local j = jobs[id]
  if not j or j.term then
    error('Invalid channel id', 2)
  end
  return F.ArtemisJobInfo(j.handle).process
end

function M.jobwait(ids, timeout)
  timeout = timeout or -1
  local results = {}
  for i, id in ipairs(ids) do
    local j = jobs[id]
    if not j then
      results[i] = -3
    else
      local done = vim.wait(timeout < 0 and 2 ^ 31 or timeout, function()
        return j.finished
      end, 5)
      results[i] = done and j.exited or -1
    end
  end
  return results
end

------------------------------------------------------------- vim.system
local SystemObj = {}
SystemObj.__index = SystemObj

function SystemObj:wait(timeout)
  local ok = vim.wait(timeout or 2 ^ 31, function()
    return self._done
  end, 5)
  if not ok then
    self:kill(15)
    vim.wait(1000, function()
      return self._done
    end, 5)
    return { code = 124, signal = 15, stdout = '', stderr = '' }
  end
  return self._result
end

function SystemObj:kill(sig)
  F.ArtemisJobStop(self._job, sig == 9 and 'kill' or 'term')
end

function SystemObj:write(data)
  if data == nil then
    F.ArtemisChanCloseIn(self._chan)
  else
    F.ArtemisChanSend(self._chan, type(data) == 'table' and table.concat(data) or data)
  end
end

function SystemObj:is_closing()
  return self._done == true
end

function M.system(cmd, opts, on_exit)
  if type(opts) == 'function' then
    on_exit, opts = opts, nil
  end
  opts = opts or {}
  local obj = setmetatable({ pid = nil }, SystemObj)
  local out, err = {}, {}
  local exited, closed = nil, 0

  local function finish()
    if obj._done or exited == nil or closed < 2 then
      return
    end
    local stdout, stderr = table.concat(out), table.concat(err)
    if opts.text then
      stdout, stderr = stdout:gsub('\r\n', '\n'), stderr:gsub('\r\n', '\n')
    end
    obj._result = {
      code = exited,
      signal = 0,
      stdout = opts.stdout == false and nil or stdout,
      stderr = opts.stderr == false and nil or stderr,
    }
    obj._done = true
    if on_exit then
      on_exit(obj._result)
    end
  end

  local vopts = {
    mode = 'raw',
    out_io = 'pipe',
    err_io = 'pipe',
    out_cb = function(_, msg)
      if type(opts.stdout) == 'function' then
        opts.stdout(nil, msg)
      end
      out[#out + 1] = msg
    end,
    err_cb = function(_, msg)
      if type(opts.stderr) == 'function' then
        opts.stderr(nil, msg)
      end
      err[#err + 1] = msg
    end,
    exit_cb = function(_, code)
      exited = code
      finish()
    end,
    close_cb = function()
      closed = 2
      finish()
    end,
  }
  if opts.cwd then
    vopts.cwd = opts.cwd
  end
  if opts.env then
    vopts.env = opts.env
  end
  obj._job = F.ArtemisJobStart(cmd, vopts)
  if F.ArtemisJobStatus(obj._job) == 'fail' then
    error('ENOENT: no such file or directory (cmd): ' .. tostring(cmd[1]), 2)
  end
  obj._chan = obj._job
  obj.pid = F.ArtemisJobInfo(obj._job).process
  if opts.stdin then
    if type(opts.stdin) == 'string' or type(opts.stdin) == 'table' then
      obj:write(opts.stdin)
      obj:write(nil)
    end
  end
  if opts.timeout then
    F.timer_start(opts.timeout, function()
      if not obj._done then
        obj:kill(15)
      end
    end)
  end
  return obj
end

return M
