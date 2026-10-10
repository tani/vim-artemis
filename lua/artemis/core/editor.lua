-- L4/L5: the non-`vim.api` parts of Neovim's `vim` namespace for Vim:
-- vim.fn, vim.g/b/w/t/v, vim.cmd, vim.schedule, vim.notify, ...
-- Vendored Neovim modules (_options, keymap, ui) are layered on top.
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')
local u = require('artemis.api.util')
local F = u.F

local M = {}
local MISSING = '__artemis_missing__'

local function vstr(s)
  return u.vstr(s)
end

------------------------------------------------------------------- vim.fn
-- Functions that exist in Neovim only; used when Vim has no such function.
local fn_shims = {
  stdpath = function(what)
    local home = os.getenv('HOME') or ''
    local dirs = {
      config = (os.getenv('XDG_CONFIG_HOME') or (home .. '/.config')) .. '/nvim',
      data = (os.getenv('XDG_DATA_HOME') or (home .. '/.local/share')) .. '/nvim',
      cache = (os.getenv('XDG_CACHE_HOME') or (home .. '/.cache')) .. '/nvim',
      state = (os.getenv('XDG_STATE_HOME') or (home .. '/.local/state')) .. '/nvim',
    }
    dirs.log = dirs.state
    dirs.run = (os.getenv('TMPDIR') or '/tmp') .. '/nvim'
    if what == 'config_dirs' or what == 'data_dirs' then
      return {}
    end
    if not dirs[what] then
      error('E5113: Invalid stdpath: ' .. tostring(what), 0)
    end
    return dirs[what]
  end,
}

-- Emulated Neovim version for has('nvim-X.Y.Z') queries (the vendored runtime).
local NVIM_EMU = { 0, 10, 4 }

local function has_nvim_version(feature)
  local a, b, c = feature:match('^nvim%-(%d+)%.(%d+)%.?(%d*)$')
  if not a then
    return nil
  end
  local want = { tonumber(a), tonumber(b), tonumber(c) or 0 }
  for i = 1, 3 do
    if want[i] ~= NVIM_EMU[i] then
      return want[i] < NVIM_EMU[i] and 1 or 0
    end
  end
  return 1
end

local function job_shims()
  local job = require('artemis.core.job')
  fn_shims.jobstart = job.jobstart
  fn_shims.jobstop = job.jobstop
  fn_shims.chansend = job.chansend
  fn_shims.chanclose = job.chanclose
  fn_shims.jobpid = job.jobpid
  fn_shims.jobwait = job.jobwait
end

local function make_fn()
  return setmetatable({}, {
    __index = function(t, name)
      local shim = fn_shims[name]
      local f
      if shim and host.eval('exists("*' .. name .. '")') == 0 then
        f = shim
      else
        f = function(...)
          local n = select('#', ...)
          local args = { ... }
          if name == 'has' and type(args[1]) == 'string' then
            local v = has_nvim_version(args[1])
            if v then
              return v
            end
          end
          for i = 1, n do
            args[i] = convert.to_vim(args[i])
          end
          return convert.from_vim(host.call_args(name, n, args))
        end
      end
      rawset(t, name, f)
      return f
    end,
  })
end

---------------------------------------------------------------- variables
local function var_accessor(getf, setf)
  return setmetatable({}, {
    __index = function(_, k)
      local v = getf(k)
      if v == MISSING then
        return nil
      end
      return v
    end,
    __newindex = function(_, k, v)
      setf(k, v)
    end,
  })
end

local function scoped(getter, setter, current)
  -- T.foo → current handle; T[n].foo → handle n
  local cache = {}
  return setmetatable({}, {
    __index = function(_, k)
      if type(k) == 'number' then
        cache[k] = cache[k]
          or var_accessor(function(name)
            return getter(k, name)
          end, function(name, v)
            setter(k, name, v)
          end)
        return cache[k]
      end
      local v = getter(current(), k)
      if v == MISSING then
        return nil
      end
      return v
    end,
    __newindex = function(_, k, v)
      setter(current(), k, v)
    end,
  })
end

local function install_vars()
  local native_g = vim.g
  vim.g = var_accessor(function(k)
    local found, sv = u.shadow_get('g', k)
    if found then
      return sv
    end
    return convert.from_vim(host.eval(string.format('get(g:, %s, %s)', vstr(k), vstr(MISSING))))
  end, function(k, v)
    if v == nil then
      u.delvar_dict(host.eval('g:'), k, 'g')
    else
      u.setvar_dict(host.eval('g:'), k, v, 'g')
    end
  end)

  vim.v = var_accessor(function(k)
    local ok, v = pcall(host.eval, 'v:' .. k)
    if not ok then
      return MISSING
    end
    return convert.from_vim(v)
  end, function(k, v)
    vim.g.ArtemisVarval = convert.to_vim(v)
    host.exec('let v:' .. k .. ' = g:ArtemisVarval')
  end)

  local function setvar(setter, unsetter)
    return function(h, k, v)
      if v == nil then
        unsetter(h, k)
      else
        setter(h, k, v)
      end
    end
  end

  local function bufid(h)
    return h == 0 and F.bufnr('%') or h
  end
  local function winid(h)
    return h == 0 and F.win_getid() or h
  end
  local function tabid(h)
    return h == 0 and F.tabpagenr() or h
  end

  vim.b = scoped(function(h, k)
    h = bufid(h)
    local found, sv = u.shadow_get('b:' .. h, k)
    if found then
      return sv
    end
    return F.getbufvar(h, k, MISSING)
  end, setvar(function(h, k, v)
    h = bufid(h)
    u.setvar_dict(host.call('getbufvar', h, ''), k, v, 'b:' .. h)
  end, function(h, k)
    h = bufid(h)
    u.delvar_dict(host.call('getbufvar', h, ''), k, 'b:' .. h)
  end), function()
    return 0
  end)

  vim.w = scoped(function(h, k)
    h = winid(h)
    local found, sv = u.shadow_get('w:' .. h, k)
    if found then
      return sv
    end
    return F.getwinvar(h, k, MISSING)
  end, setvar(function(h, k, v)
    h = winid(h)
    u.setvar_dict(host.call('getwinvar', h, ''), k, v, 'w:' .. h)
  end, function(h, k)
    h = winid(h)
    u.delvar_dict(host.call('getwinvar', h, ''), k, 'w:' .. h)
  end), function()
    return 0
  end)

  vim.t = scoped(function(h, k)
    h = tabid(h)
    local found, sv = u.shadow_get('t:' .. h, k)
    if found then
      return sv
    end
    return F.gettabvar(h, k, MISSING)
  end, setvar(function(h, k, v)
    h = tabid(h)
    u.setvar_dict(host.call('gettabvar', h, ''), k, v, 't:' .. h)
  end, function(h, k)
    h = tabid(h)
    u.delvar_dict(host.call('gettabvar', h, ''), k, 't:' .. h)
  end), function()
    return 0
  end)
end

------------------------------------------------------------------ vim.cmd
local function install_cmd()
  vim.cmd = setmetatable({}, {
    __call = function(_, command)
      if type(command) == 'table' then
        return vim.api.nvim_cmd(command, {})
      end
      return vim.api.nvim_exec2(command, { output = true }).output
    end,
    __index = function(t, command)
      t[command] = function(...)
        local opts
        if select('#', ...) == 1 and type((...)) == 'table' then
          opts = (...)
          if opts.args == nil then
            opts.args = {}
          end
          for i, v in ipairs(opts) do
            opts.args[i] = v
          end
        else
          opts = { args = { ... } }
        end
        opts.cmd = command
        return vim.api.nvim_cmd(opts, {})
      end
      return t[command]
    end,
  })
end

---------------------------------------------------------- scheduling etc.
local function install_misc()
  vim.log = vim.log or { levels = { TRACE = 0, DEBUG = 1, INFO = 2, WARN = 3, ERROR = 4, OFF = 5 } }

  function vim.schedule(fn)
    F.timer_start(0, function()
      fn()
    end)
  end

  function vim.schedule_wrap(fn)
    return function(...)
      local args = { ... }
      local n = select('#', ...)
      vim.schedule(function()
        local unpack = unpack or table.unpack
        fn(unpack(args, 1, n))
      end)
    end
  end

  function vim.defer_fn(fn, timeout)
    local id = F.timer_start(timeout, function()
      fn()
    end)
    return {
      stop = function()
        F.timer_stop(id)
      end,
      close = function()
        F.timer_stop(id)
      end,
      is_closing = function()
        return false
      end,
    }
  end

  function vim.in_fast_event()
    return false
  end

  function vim.on_key()
    return 0
  end

  function vim.wait(timeout, cond, interval, fast_only)
    interval = interval or 200
    local start = F.reltime()
    local function elapsed()
      return F.float2nr(F.reltimefloat(F.reltime(start)) * 1000)
    end
    local function check()
      if cond then
        local ok, res = pcall(cond)
        if ok and res then
          return true
        end
      end
      return false
    end
    if check() then
      return true, nil
    end
    while elapsed() < timeout do
      host.exec('sleep ' .. math.min(interval, 10) .. 'm')
      if check() then
        return true, nil
      end
    end
    if cond then
      return false, -1
    end
    return true, nil
  end

  local hl_by_level = { [3] = 'WarningMsg', [4] = 'ErrorMsg' }
  function vim.notify(msg, level, opts)
    level = level or 2
    if level < (vim.g.__artemis_loglevel or 0) then
      return
    end
    vim.api.nvim_echo({ { tostring(msg), hl_by_level[level] } }, true, {})
  end

  local notified = {}
  function vim.notify_once(msg, level, opts)
    if not notified[msg] then
      notified[msg] = true
      vim.notify(msg, level, opts)
      return true
    end
    return false
  end

  function vim.print(...)
    local n = select('#', ...)
    local out = {}
    for i = 1, n do
      local v = select(i, ...)
      out[#out + 1] = type(v) == 'string' and v or vim.inspect(v)
    end
    vim.api.nvim_out_write(table.concat(out, ' ') .. '\n')
    return ...
  end

  -- UTF helpers (pure Lua)
  local function char_len(b)
    if b >= 0xF0 then return 4 elseif b >= 0xE0 then return 3 elseif b >= 0xC0 then return 2 end
    return 1
  end
  function vim.str_utfindex(s, index)
    index = index or #s
    if index > #s then
      error('index out of range', 2)
    end
    local i, u32, u16 = 1, 0, 0
    while i <= index do
      local l = char_len(s:byte(i))
      u32 = u32 + 1
      u16 = u16 + (l == 4 and 2 or 1)
      i = i + l
    end
    return u32, u16
  end
  function vim.str_byteindex(s, index, use_utf16)
    local i, n = 1, 0
    while n < index do
      if i > #s then
        error('index out of range', 2)
      end
      local l = char_len(s:byte(i))
      n = n + ((use_utf16 and l == 4) and 2 or 1)
      i = i + l
    end
    return i - 1
  end

  function vim.keycode(str)
    return vim.api.nvim_replace_termcodes(str, true, true, true)
  end

  function vim.regex(re)
    local obj = {}
    function obj:match_str(s)
      local r = F.matchstrpos(s, re)
      if r[2] < 0 then
        return nil
      end
      return r[2], r[3]
    end
    function obj:match_line(buf, line, s, e)
      local text = F.getbufline(buf == 0 and F.bufnr('%') or buf, line + 1, line + 1)[1] or ''
      s = s or 0
      local sub = text:sub(s + 1, e)
      local r = F.matchstrpos(sub, re)
      if r[2] < 0 then
        return nil
      end
      return r[2] + s, r[3] + s
    end
    return obj
  end

  vim.json = vim.json or {
    encode = function(obj)
      return F.json_encode(obj)
    end,
    decode = function(str, opts)
      return F.json_decode(str)
    end,
  }
end

------------------------------------------------------------------- setup
function M.setup()
  if host.kind ~= 'vim' then
    return
  end
  job_shims()
  vim.fn = make_fn()
  vim.api = require('artemis.api.init')
  vim.uv = require('artemis.core.uv')
  vim.loop = vim.uv
  vim.system = require('artemis.core.job').system
  vim.fs = require('artemis.vendor.nvim.fs')
  vim.filetype = require('artemis.core.filetype')
  package.preload['vim.filetype'] = function() return vim.filetype end
  install_vars()
  install_cmd()
  install_misc()
  require('artemis.core.stubs').setup()
  require('artemis.core.hlgroups').setup()
  -- Neovim's own pure-Lua implementations on top of vim.api.
  require('artemis.vendor.nvim._options')
  vim.keymap = require('artemis.vendor.nvim.keymap')
  vim.ui = require('artemis.vendor.nvim.ui')
  vim.api.keyset = vim.api.keyset or {}
  for _, m in ipairs({ 'keymap', 'ui' }) do
    package.preload['vim.' .. m] = package.preload['vim.' .. m]
      or function()
        return vim[m]
      end
  end
end

return M
