-- vim.api: eval/exec, messages, input, highlight, namespaces and misc.
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy

local ns_by_name, ns_by_id, ns_next = {}, {}, 0

local function build_cmd(cmd)
  local parts = {}
  local mods = cmd.mods or {}
  local function flag(name, text)
    if mods[name] then
      parts[#parts + 1] = text or name
    end
  end
  if mods.silent then parts[#parts + 1] = mods.emsg_silent and 'silent!' or 'silent' end
  flag('unsilent')
  flag('noautocmd')
  flag('keepjumps')
  flag('keepmarks')
  flag('keeppatterns')
  flag('keepalt')
  flag('lockmarks')
  flag('sandbox')
  flag('noswapfile')
  flag('confirm')
  if mods.tab and mods.tab >= 0 then parts[#parts + 1] = mods.tab .. 'tab' end
  if mods.vertical then parts[#parts + 1] = 'vertical' end
  if mods.split and mods.split ~= '' then parts[#parts + 1] = mods.split end
  local range = ''
  if cmd.range then
    range = table.concat(cmd.range, ',')
  end
  local c = (cmd.count and tostring(cmd.count) or '') .. cmd.cmd
  parts[#parts + 1] = range .. c .. (cmd.bang and '!' or '')
  for _, a in ipairs(cmd.args or {}) do
    parts[#parts + 1] = tostring(a)
  end
  if cmd.reg then
    parts[#parts + 1] = cmd.reg
  end
  return table.concat(parts, ' ')
end

return function(A)
  function A.nvim_eval(expr)
    return convert.from_vim(host.eval(expr))
  end

  function A.nvim_command(cmd)
    host.exec(cmd)
  end

  function A.nvim_exec(src, output)
    local out = host.exec(src)
    return output and out or ''
  end

  function A.nvim_exec2(src, opts)
    local out = host.exec(src)
    if opts and opts.output then
      return { output = out }
    end
    return {}
  end

  function A.nvim_cmd(cmd, opts)
    local out = host.exec(build_cmd(cmd))
    if opts and opts.output then
      return out
    end
    return ''
  end

  function A.nvim_call_function(name, args)
    local unpack = unpack or table.unpack
    return F[name](unpack(args or {}, 1, #(args or {})))
  end

  function A.nvim_get_current_line()
    return F.getline('.')
  end

  function A.nvim_set_current_line(line)
    F.setline('.', line)
  end

  function A.nvim_del_current_line()
    host.exec('normal! "_dd')
  end

  function A.nvim_get_mode()
    return { mode = F.mode(1), blocking = false }
  end

  function A.nvim_strwidth(s)
    return F.strdisplaywidth(s)
  end

  function A.nvim_feedkeys(keys, mode, escape_ks)
    mode = (mode or ''):gsub('R', '')
    F.feedkeys(keys, mode)
  end

  function A.nvim_input(keys)
    F.feedkeys(require('artemis.api.cmd').replace_termcodes(keys, true, true, true), 'it')
    return #keys
  end

  -- messages
  local function out(text, hl)
    host.exec('echohl ' .. (hl or 'None'))
    vim.g.__artemis_echo = text
    local ok, e = pcall(host.exec, 'echon g:__artemis_echo')
    host.exec('echohl None')
    if not ok then
      error(e, 0)
    end
  end
  function A.nvim_out_write(s)
    out(s)
  end
  function A.nvim_err_write(s)
    out(s, 'ErrorMsg')
  end
  function A.nvim_err_writeln(s)
    vim.g.__artemis_echo = s
    host.exec('echohl ErrorMsg | echomsg g:__artemis_echo | echohl None')
  end
  function A.nvim_echo(chunks, history, opts)
    local text = {}
    for _, c in ipairs(chunks) do
      local hl = c[2]
      if type(hl) == 'table' then
        hl = hl[1]
      end
      out(c[1], hl)
      text[#text + 1] = c[1]
    end
    if history then
      vim.g.__artemis_echo = table.concat(text)
      host.exec('echomsg g:__artemis_echo')
    end
  end

  function A.nvim_put(lines, regtype, after, follow)
    local save, savetype = F.getreg('z', 1, 1), F.getregtype('z')
    F.setreg('z', lines, regtype == '' and 'c' or regtype)
    local ok, e = pcall(host.exec, 'normal! "z' .. (follow and 'g' or '') .. (after and 'p' or 'P'))
    F.setreg('z', save, savetype)
    if not ok then
      error(e, 0)
    end
  end

  -- runtime files
  function A.nvim_list_runtime_paths()
    return F.split(vim.o and vim.o.runtimepath or host.eval('&rtp'), ',')
  end
  function A.nvim_get_runtime_file(name, all)
    local files = F.globpath(host.eval('&rtp'), name, 1, 1)
    if not all then
      return { files[1] }
    end
    return files
  end

  -- namespaces
  function A.nvim_create_namespace(name)
    if name ~= '' and ns_by_name[name] then
      return ns_by_name[name]
    end
    ns_next = ns_next + 1
    if name ~= '' then
      ns_by_name[name] = ns_next
    end
    ns_by_id[ns_next] = name
    return ns_next
  end
  function A.nvim_get_namespaces()
    return vim.deepcopy and vim.deepcopy(ns_by_name) or ns_by_name
  end

  -- highlight
  function A.nvim_get_hl_id_by_name(name)
    return F.hlID(name)
  end

  local function to_nvim_hl(d)
    local out = {}
    local function color(c)
      if type(c) == 'string' and c:match('^#%x%x%x%x%x%x$') then
        return tonumber(c:sub(2), 16)
      end
      return c
    end
    if d.linksto then
      out.link = d.linksto
    end
    if d.guifg then out.fg = color(d.guifg) end
    if d.guibg then out.bg = color(d.guibg) end
    if d.guisp then out.sp = color(d.guisp) end
    if d.ctermfg then out.ctermfg = tonumber(d.ctermfg) or d.ctermfg end
    if d.ctermbg then out.ctermbg = tonumber(d.ctermbg) or d.ctermbg end
    for _, key in ipairs({ 'gui', 'cterm' }) do
      for a, on in pairs(d[key] or {}) do
        if on then out[a] = true end
      end
    end
    if d.default then out.default = true end
    return out
  end

  function A.nvim_get_hl(ns, opts)
    opts = opts or {}
    local resolve = opts.link == false
    if opts.name or opts.id then
      local name = opts.name or F.synIDattr(opts.id, 'name')
      local list = F.hlget(name, resolve)
      if #list == 0 then
        return {}
      end
      return to_nvim_hl(list[1])
    end
    local all = {}
    for _, d in ipairs(F.hlget(nil, resolve)) do
      all[d.name] = to_nvim_hl(d)
    end
    return all
  end

  function A.nvim_list_uis()
    return {}
  end
  function A.nvim_get_chan_info()
    return {}
  end
  function A.nvim_list_chans()
    return {}
  end

  local attrs = { 'bold', 'italic', 'underline', 'undercurl', 'strikethrough', 'reverse', 'standout' }
  function A.nvim_set_hl(ns, name, val)
    local def = { name = name }
    if val.link then
      def.linksto = val.link
      F.hlset({ def })
      return
    end
    local list = {}
    for _, a in ipairs(attrs) do
      if val[a] then
        list[#list + 1] = a == 'strikethrough' and 'strikethrough' or a
      end
    end
    local function color(c)
      if type(c) == 'number' then
        return string.format('#%06x', c)
      end
      return c
    end
    if val.fg then def.guifg = color(val.fg) end
    if val.bg then def.guibg = color(val.bg) end
    if val.sp then def.guisp = color(val.sp) end
    if val.ctermfg then def.ctermfg = tostring(val.ctermfg) end
    if val.ctermbg then def.ctermbg = tostring(val.ctermbg) end
    if #list > 0 then
      local a = {}
      for _, k in ipairs(list) do
        a[k] = true
      end
      def.gui = a
      def.cterm = a
    end
    F.hlset({ def })
  end
end
