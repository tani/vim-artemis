-- vim.api user commands, autocmds and keymaps.
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')
local registry = require('artemis.core.registry')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy

local M = {}

------------------------------------------------------------------ termcodes
--- nvim_replace_termcodes: translate `<Key>` notation to internal key codes.
function M.replace_termcodes(str, from_part, do_lt, special)
  if special == false then
    return str
  end
  return (
    str:gsub('<([^<>%s]+)>', function(name)
      local lname = name:lower()
      if lname == 'lt' then
        return do_lt == false and '<lt>' or '<'
      elseif lname == 'leader' then
        return vim.g.mapleader or '\\'
      elseif lname == 'localleader' then
        return vim.g.maplocalleader or '\\'
      end
      local ok, res = pcall(host.eval, '"\\<' .. name:gsub('"', '\\"') .. '>"')
      if ok and type(res) == 'string' and res ~= '' then
        return res
      end
      return '<' .. name .. '>'
    end)
  )
end

------------------------------------------------------------------- commands
local function build_command(name, body, opts, buffer)
  local flags = {}
  if buffer then
    flags[#flags + 1] = '-buffer'
  end
  local nargs = opts.nargs
  if nargs ~= nil then
    flags[#flags + 1] = '-nargs=' .. tostring(nargs)
  end
  if opts.range ~= nil and opts.range ~= false then
    flags[#flags + 1] = opts.range == true and '-range' or '-range=' .. tostring(opts.range)
  end
  if opts.count ~= nil and opts.count ~= false then
    flags[#flags + 1] = opts.count == true and '-count' or '-count=' .. tostring(opts.count)
  end
  if opts.addr then
    flags[#flags + 1] = '-addr=' .. opts.addr
  end
  if opts.bang then
    flags[#flags + 1] = '-bang'
  end
  if opts.bar then
    flags[#flags + 1] = '-bar'
  end
  if opts.register then
    flags[#flags + 1] = '-register'
  end
  if type(opts.complete) == 'string' then
    flags[#flags + 1] = '-complete=' .. opts.complete
  end
  local bang = opts.force == false and '' or '!'
  return 'command' .. bang .. ' ' .. table.concat(flags, ' ') .. ' ' .. name .. ' ' .. body
end

--- Called from the generated `:command` body.
function M.run_command(id, name, args, fargs, bang, line1, line2, count, range, reg, mods)
  local fn = registry.get(id)
  if not fn then
    error('artemis: command ' .. name .. ' has been released', 0)
  end
  return fn({
    name = name,
    args = args,
    fargs = fargs,
    nargs = nil,
    bang = bang,
    line1 = line1,
    line2 = line2,
    range = range,
    count = count,
    reg = reg,
    mods = mods,
    smods = {},
  })
end

local cmd_ids = {}

local function define_command(name, command, opts, buffer)
  opts = opts or {}
  if not name:match('^%u[%w_]*$') then
    error('Invalid command name (must start with uppercase): ' .. name, 3)
  end
  local key = (buffer or 0) .. ':' .. name
  local body
  if type(command) == 'function' then
    if cmd_ids[key] then
      registry.del(cmd_ids[key])
    end
    local id = registry.add(command)
    cmd_ids[key] = id
    body = string.format(
      "lua require('artemis.api.cmd').run_command(%d, %q, <q-args>, {<f-args>}, "
        .. '<q-bang> == "!", <line1>, <line2>, <count>, <range>, <q-reg>, <q-mods>)',
      id,
      name
    )
  else
    body = command
  end
  local def = build_command(name, body, opts, buffer ~= nil)
  if buffer and buffer ~= 0 and buffer ~= F.bufnr('%') then
    local nb = require('artemis.api.init')
    nb.nvim_buf_call(buffer, function()
      host.exec(def)
    end)
  else
    host.exec(def)
  end
end

------------------------------------------------------------------- autocmds
local aug_by_name, aug_by_id, aug_next = {}, {}, 0
local autocmd_data

local function group_name(g)
  if g == nil then
    return nil
  end
  if type(g) == 'number' then
    local n = aug_by_id[g]
    if not n then
      error('Invalid augroup id: ' .. g, 3)
    end
    return n
  end
  return g
end

local function as_list(x)
  if x == nil then
    return {}
  end
  if type(x) == 'table' then
    return x
  end
  return { x }
end

local autocmd_specs = {}

function M.run_autocmd(id, event, group)
  local fn = registry.get(id)
  if not fn then
    return
  end
  local buf = tonumber(F.expand('<abuf>'))
  local res = fn({
    id = id,
    event = event,
    group = group and aug_by_name[group] or nil,
    match = F.expand('<amatch>'),
    buf = buf,
    file = F.expand('<afile>'),
    data = autocmd_data,
  })
  if res == true then
    registry.del(id)
  end
end

--------------------------------------------------------------------- keymaps
local map_ids = {}

local function map_cmd_lhs(lhs)
  return (lhs:gsub(' ', '<Space>'):gsub('|', '<Bar>'))
end

local function norm_mode(mode)
  if mode == '' or mode == nil then
    return ' '
  end
  return mode
end

local function set_keymap(buf, mode, lhs, rhs, opts)
  opts = opts or {}
  mode = norm_mode(mode)
  local key = table.concat({ mode, buf or 0, lhs }, '\0')
  if map_ids[key] then
    registry.del(map_ids[key])
    map_ids[key] = nil
  end
  local callback = opts.callback
  if callback == nil and type(rhs) == 'function' then
    callback = rhs
  end
  local mrhs = rhs
  if callback then
    local id = registry.add(function()
      local r = callback()
      if opts.expr and opts.replace_keycodes ~= false and type(r) == 'string' then
        r = M.replace_termcodes(r, true, true, true)
      end
      return r
    end)
    map_ids[key] = id
    if opts.expr then
      mrhs = string.format('luaeval(\'require("artemis.core.registry").call(%d)\')', id)
    else
      mrhs = string.format('<Cmd>lua require("artemis.core.registry").call(%d)<CR>', id)
    end
  elseif type(rhs) ~= 'string' then
    error('rhs must be a string or function', 3)
  end
  local raw = M.replace_termcodes(lhs, true, true, true)
  local def = {
    lhs = raw,
    lhsraw = raw,
    rhs = mrhs,
    mode = mode,
    noremap = opts.noremap and 1 or 0,
    silent = opts.silent and 1 or 0,
    expr = opts.expr and 1 or 0,
    nowait = opts.nowait and 1 or 0,
    script = opts.script and 1 or 0,
    buffer = buf and 1 or 0,
  }
  if opts.unique and F.maparg(raw, mode == ' ' and '' or mode, 0, 1).lhs then
    error('E227: mapping already exists for ' .. lhs, 3)
  end
  local function apply()
    F.mapset(mode, 0, def)
  end
  if buf and buf ~= 0 and buf ~= F.bufnr('%') then
    require('artemis.api.init').nvim_buf_call(buf, apply)
  else
    apply()
  end
end

local function del_keymap(buf, mode, lhs)
  mode = norm_mode(mode)
  local cmd = (mode == ' ' and '' or mode == '!' and '' or mode) .. 'unmap'
  if mode == '!' then
    cmd = 'unmap!'
  end
  local def = cmd .. (buf and ' <buffer> ' or ' ') .. map_cmd_lhs(lhs)
  local function apply()
    host.exec(def)
  end
  if buf and buf ~= 0 and buf ~= F.bufnr('%') then
    require('artemis.api.init').nvim_buf_call(buf, apply)
  else
    apply()
  end
  local key = table.concat({ mode, buf or 0, lhs }, '\0')
  if map_ids[key] then
    registry.del(map_ids[key])
    map_ids[key] = nil
  end
end

local function get_keymaps(mode, buf)
  local out = {}
  mode = norm_mode(mode)
  for _, d in ipairs(F.maplist()) do
    local isbuf = d.buffer == 1
    if (buf and isbuf) or (not buf and not isbuf) then
      local dm = d.mode
      local match = dm:find(mode == ' ' and '%s' or '[' .. mode:gsub('%p', '%%%0') .. ']')
      if match or (mode == ' ' and dm == ' ') then
        out[#out + 1] = {
          lhs = d.lhs,
          lhsraw = d.lhsraw,
          rhs = d.rhs,
          mode = d.mode,
          noremap = d.noremap,
          nowait = d.nowait,
          silent = d.silent,
          expr = d.expr,
          buffer = d.buffer,
          script = d.script,
          sid = d.sid,
          lnum = d.lnum,
          abbr = d.abbr or 0,
        }
      end
    end
  end
  return out
end

------------------------------------------------------------------- installer
return setmetatable(M, {
  __call = function(_, A)
    A.nvim_replace_termcodes = M.replace_termcodes

    function A.nvim_create_user_command(name, command, opts)
      define_command(name, command, opts, nil)
    end
    function A.nvim_buf_create_user_command(buf, name, command, opts)
      define_command(name, command, opts, u.buf(buf))
    end
    function A.nvim_del_user_command(name)
      host.exec('delcommand ' .. name)
      local id = cmd_ids['0:' .. name]
      if id then
        registry.del(id)
        cmd_ids['0:' .. name] = nil
      end
    end
    function A.nvim_buf_del_user_command(buf, name)
      buf = u.buf(buf)
      A.nvim_buf_call(buf, function()
        host.exec('delcommand ' .. name)
      end)
    end

    -- augroups
    function A.nvim_create_augroup(name, opts)
      opts = opts or {}
      host.exec('augroup ' .. name .. (opts.clear ~= false and ' | autocmd!' or '') .. ' | augroup END')
      if not aug_by_name[name] then
        aug_next = aug_next + 1
        aug_by_name[name] = aug_next
        aug_by_id[aug_next] = name
      end
      return aug_by_name[name]
    end
    function A.nvim_del_augroup_by_name(name)
      host.exec('augroup ' .. name .. ' | autocmd! | augroup END | augroup! ' .. name)
      local id = aug_by_name[name]
      aug_by_name[name] = nil
      if id then
        aug_by_id[id] = nil
      end
    end
    function A.nvim_del_augroup_by_id(id)
      A.nvim_del_augroup_by_name(group_name(id))
    end

    function A.nvim_create_autocmd(event, opts)
      opts = opts or {}
      if opts.callback and opts.command then
        error("cannot pass both: 'callback' and 'command' for the same autocmd", 2)
      end
      local group = group_name(opts.group)
      local patterns = as_list(opts.pattern)
      if opts.buffer ~= nil then
        patterns = { '<buffer=' .. (opts.buffer == 0 and F.bufnr('%') or opts.buffer) .. '>' }
      end
      if #patterns == 0 then
        patterns = { '*' }
      end
      local id
      local events = as_list(event)
      local specs = {}
      for _, ev in ipairs(events) do
        local body
        if opts.callback then
          if not id then
            local cb = opts.callback
            if type(cb) == 'string' then
              local name = cb
              cb = function(args)
                return F[name](args)
              end
            end
            id = registry.add(cb)
          end
          body = string.format(
            "lua require('artemis.api.cmd').run_autocmd(%d, %q, %s)",
            id,
            ev,
            group and string.format('%q', group) or 'nil'
          )
        else
          body = opts.command or ''
        end
        specs[#specs + 1] = {
          event = ev,
          group = group,
          pattern = table.concat(patterns, ','),
          cmd = body,
          once = opts.once and 1 or 0,
          ['nested'] = opts.nested and 1 or 0,
        }
      end
      if not id then
        id = registry.add(function() end)
      end
      F.autocmd_add(specs)
      return id
    end

    function A.nvim_del_autocmd(id)
      registry.del(id)
    end

    function A.nvim_clear_autocmds(opts)
      opts = opts or {}
      local patterns = as_list(opts.pattern)
      if opts.buffer ~= nil then
        patterns = { '<buffer=' .. (opts.buffer == 0 and F.bufnr('%') or opts.buffer) .. '>' }
      end
      local pat = #patterns > 0 and table.concat(patterns, ',') or '*'
      local events = as_list(opts.event)
      if #events == 0 then
        events = { '*' }
      end
      local specs = {}
      for _, ev in ipairs(events) do
        specs[#specs + 1] = { event = ev, group = group_name(opts.group), pattern = pat }
      end
      F.autocmd_delete(specs)
    end

    function A.nvim_exec_autocmds(event, opts)
      opts = opts or {}
      local group = group_name(opts.group)
      local pat = opts.pattern
      if type(pat) == 'table' then
        pat = pat[1]
      end
      autocmd_data = opts.data
      local function run()
        for _, ev in ipairs(as_list(event)) do
          local cmd = 'silent doautocmd '
            .. (opts.modeline == false and '<nomodeline> ' or '')
            .. (group and (group .. ' ') or '')
            .. ev
            .. (pat and (' ' .. pat) or '')
          host.exec(cmd)
        end
      end
      local ok, err
      if opts.buffer and opts.buffer ~= 0 then
        ok, err = pcall(A.nvim_buf_call, opts.buffer, run)
      else
        ok, err = pcall(run)
      end
      autocmd_data = nil
      if not ok then
        error(err, 0)
      end
    end

    function A.nvim_get_autocmds(opts)
      opts = opts or {}
      local q = {}
      if opts.group ~= nil then
        q.group = group_name(opts.group)
      end
      if opts.event then
        q.event = as_list(opts.event)[1]
      end
      if opts.pattern then
        q.pattern = as_list(opts.pattern)[1]
      end
      local out = {}
      for _, a in ipairs(F.autocmd_get(q)) do
        out[#out + 1] = {
          group_name = a.group,
          group = a.group and aug_by_name[a.group] or nil,
          event = a.event,
          pattern = a.pattern,
          command = a.cmd,
          once = a.once == 1,
          buflocal = a.bufnr ~= nil,
          buffer = a.bufnr,
        }
      end
      return out
    end

    -- keymaps
    function A.nvim_set_keymap(mode, lhs, rhs, opts)
      set_keymap(nil, mode, lhs, rhs, opts)
    end
    function A.nvim_buf_set_keymap(buf, mode, lhs, rhs, opts)
      set_keymap(u.buf(buf), mode, lhs, rhs, opts)
    end
    function A.nvim_del_keymap(mode, lhs)
      del_keymap(nil, mode, lhs)
    end
    function A.nvim_buf_del_keymap(buf, mode, lhs)
      del_keymap(u.buf(buf), mode, lhs)
    end
    function A.nvim_get_keymap(mode)
      return get_keymaps(mode, false)
    end
    function A.nvim_buf_get_keymap(buf, mode)
      local list
      A.nvim_buf_call(buf, function()
        list = get_keymaps(mode, true)
      end)
      return list
    end
  end,
})
