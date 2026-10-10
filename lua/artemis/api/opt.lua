-- vim.api option and variable functions.
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')
local u = require('artemis.api.util')
local optinfo = require('artemis.core.optinfo')
local F, truthy = u.F, u.truthy
local MISSING = '__artemis_missing__'

local by_short
local function resolve(name)
  if optinfo[name] then
    return name, optinfo[name]
  end
  if not by_short then
    by_short = {}
    for n, i in pairs(optinfo) do
      if i[6] ~= '' then
        by_short[i[6]] = n
      end
    end
  end
  local long = by_short[name]
  if long then
    return long, optinfo[long]
  end
end

local function check_name(name)
  if type(name) ~= 'string' or not name:match('^[%w_]+$') then
    error("Invalid option (not found): '" .. tostring(name) .. "'", 3)
  end
end

-- Options that exist in Neovim but not in Vim (statuscolumn, winbar, ...):
-- accepted and remembered, but without any effect on the editor.
local shadow = {}

--- Metadata for option `name` (static table first, then probing Vim).
local function info(name)
  check_name(name)
  local long, rec = resolve(name)
  local present = truthy(host.eval('exists("+' .. (long or name) .. '")'))
  if not present and not rec then
    error("Invalid option (not found): '" .. name .. "'", 3)
  end
  if rec then
    return {
      vimless = not present,
      name = long,
      shortname = rec[6],
      type = rec[1],
      commalist = rec[2],
      flaglist = rec[3],
      scope = rec[4],
      global_local = rec[5],
      allows_duplicates = rec[7],
      was_set = false,
    }
  end
  -- Vim-only option: probe.
  local v = host.eval('&' .. name)
  local t = type(v) == 'number' and 'number' or 'string'
  if t == 'number' then
    local shown = host.exec('set ' .. name .. '?')
    if not shown:find('=', 1, true) then
      t = 'boolean'
    end
  end
  return {
    name = name,
    shortname = '',
    type = t,
    commalist = t == 'string' and tostring(v):find(',', 1, true) ~= nil,
    flaglist = false,
    scope = 'global',
    global_local = false,
    allows_duplicates = true,
    was_set = false,
  }
end

local vlua = require('artemis.core.vlua')

-- Options holding a function name: `v:lua.f` becomes a Funcref.
local funcref_opts = {
  operatorfunc = true, completefunc = true, omnifunc = true, tagfunc = true,
  thesaurusfunc = true, quickfixtextfunc = true, findfunc = true,
}

local function to_lua(i, v)
  if i.type == 'boolean' then
    return v == 1 or v == true
  end
  return v
end

local function get(name, opts)
  opts = opts or {}
  local i = info(name)
  local n = i.name
  if i.vimless then
    local v = shadow[n]
    if v == nil then
      v = (i.type == 'boolean' and false) or (i.type == 'number' and 0) or ''
    end
    return v
  end
  local v
  if opts.win and opts.buf then
    error("Can only use one of 'buf' or 'win'", 3)
  elseif opts.win then
    v = F.getwinvar(u.win(opts.win), '&' .. n)
  elseif opts.buf then
    v = F.getbufvar(u.buf(opts.buf), '&' .. n)
  elseif opts.scope == 'local' then
    v = host.eval('&l:' .. n)
  elseif opts.scope == 'global' then
    v = host.eval('&g:' .. n)
  else
    v = host.eval('&' .. n)
  end
  return to_lua(i, v)
end

local function set(name, value, opts)
  opts = opts or {}
  local i = info(name)
  local n = i.name
  if i.vimless then
    shadow[n] = value
    return
  end
  if type(value) == 'boolean' then
    value = value and 1 or 0
  end
  if value == nil then
    error('Option value cannot be nil', 3)
  end
  if type(value) == 'string' and value:find('v:lua', 1, true) then
    local fn = funcref_opts[n] and vlua.as_function(value)
    if fn then
      value = vim.call('luaeval', '_A', fn)
    else
      value = vlua.rewrite(value)
    end
  end
  if opts.win and opts.buf then
    error("Can only use one of 'buf' or 'win'", 3)
  elseif opts.win then
    F.setwinvar(u.win(opts.win), '&' .. n, value)
    return
  elseif opts.buf then
    F.setbufvar(u.buf(opts.buf), '&' .. n, value)
    return
  end
  -- Route the value through a variable so no quoting is needed.
  vim.g.ArtemisOptval = convert.to_vim(value)
  local prefix = opts.scope == 'local' and '&l:' or opts.scope == 'global' and '&g:' or '&'
  host.exec('let ' .. prefix .. n .. ' = g:ArtemisOptval')
end

local function check_var(name)
  if type(name) ~= 'string' or not name:match('^[%w_#:]+$') then
    error('Invalid key: ' .. tostring(name), 3)
  end
end

return function(A)
  function A.nvim_get_option_value(name, opts)
    return get(name, opts)
  end
  function A.nvim_set_option_value(name, value, opts)
    return set(name, value, opts)
  end
  function A.nvim_get_option_info2(name, opts)
    return info(name)
  end
  function A.nvim_get_option(name)
    return get(name, {})
  end
  function A.nvim_set_option(name, value)
    return set(name, value, { scope = 'global' })
  end

  local function getvar(scope)
    return function(name)
      check_var(name)
      if not truthy(host.eval('exists("' .. scope .. ':' .. name .. '")')) then
        error('Key not found: ' .. name, 2)
      end
      return convert.from_vim(host.eval(scope .. ':' .. name))
    end
  end
  A.nvim_get_var = getvar('g')
  A.nvim_get_vvar = getvar('v')

  function A.nvim_set_var(name, value)
    check_var(name)
    vim.g.ArtemisVarval = convert.to_vim(value)
    host.exec('let g:' .. name .. ' = g:ArtemisVarval')
  end

  function A.nvim_set_vvar(name, value)
    check_var(name)
    vim.g.ArtemisVarval = convert.to_vim(value)
    host.exec('let v:' .. name .. ' = g:ArtemisVarval')
  end

  function A.nvim_del_var(name)
    check_var(name)
    host.exec('unlet! g:' .. name)
  end

  function A.nvim_tabpage_get_var(t, name)
    local v = F.gettabvar(u.tab(t), name, MISSING)
    if v == MISSING then
      error('Key not found: ' .. name, 2)
    end
    return v
  end
  function A.nvim_tabpage_set_var(t, name, value)
    F.settabvar(u.tab(t), name, value)
  end
  function A.nvim_tabpage_del_var(t, name)
    host.exec(string.format('call remove(gettabvar(%d, ""), %s)', u.tab(t), u.vstr(name)))
  end
end
