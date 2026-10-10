-- vim.api buffer functions.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy
local MISSING = '__artemis_missing__'

return function(A)
  function A.nvim_get_current_buf()
    return F.bufnr('%')
  end

  function A.nvim_set_current_buf(b)
    b = u.buf(b)
    host.exec('buffer ' .. b)
  end

  function A.nvim_list_bufs()
    local out = {}
    for i = 1, F.bufnr('$') do
      if truthy(F.bufexists(i)) then
        out[#out + 1] = i
      end
    end
    return out
  end

  function A.nvim_buf_is_valid(b)
    return type(b) == 'number' and truthy(F.bufexists(b))
  end

  function A.nvim_buf_is_loaded(b)
    return truthy(F.bufloaded(u.buf(b)))
  end

  function A.nvim_buf_line_count(b)
    return u.linecount(u.buf(b))
  end

  function A.nvim_buf_get_lines(b, s, e, strict)
    b = u.buf(b)
    local n = u.linecount(b)
    s, e = u.norm_range(s, e, n, strict)
    if s >= e then
      return {}
    end
    return F.getbufline(b, s + 1, e)
  end

  function A.nvim_buf_set_lines(b, s, e, strict, repl)
    b = u.buf(b)
    local n = u.linecount(b)
    s, e = u.norm_range(s, e, n, strict)
    local old, new = e - s, #repl
    local common = math.min(old, new)
    if common > 0 then
      local part = {}
      for i = 1, common do
        part[i] = repl[i]
      end
      if F.setbufline(b, s + 1, part) ~= 0 then
        error('Failed to set lines', 2)
      end
    end
    if new > old then
      local part = {}
      for i = common + 1, new do
        part[#part + 1] = repl[i]
      end
      if F.appendbufline(b, s + common, part) ~= 0 then
        error('Failed to append lines', 2)
      end
    elseif old > new then
      if F.deletebufline(b, s + new + 1, e) ~= 0 then
        error('Failed to delete lines', 2)
      end
    end
  end

  function A.nvim_buf_get_text(b, srow, scol, erow, ecol, opts)
    b = u.buf(b)
    local n = u.linecount(b)
    if srow < 0 then srow = n + srow end
    if erow < 0 then erow = n + erow end
    local lines = F.getbufline(b, srow + 1, erow + 1)
    if #lines == 0 then
      return {}
    end
    if #lines == 1 then
      lines[1] = lines[1]:sub(scol + 1, ecol)
    else
      lines[1] = lines[1]:sub(scol + 1)
      lines[#lines] = lines[#lines]:sub(1, ecol)
    end
    return lines
  end

  function A.nvim_buf_set_text(b, srow, scol, erow, ecol, repl)
    b = u.buf(b)
    local n = u.linecount(b)
    if srow < 0 then srow = n + srow end
    if erow < 0 then erow = n + erow end
    local first = F.getbufline(b, srow + 1, srow + 1)[1] or ''
    local last = F.getbufline(b, erow + 1, erow + 1)[1] or ''
    local new = {}
    for i, l in ipairs(repl) do
      new[i] = l
    end
    if #new == 0 then
      new[1] = ''
    end
    new[1] = first:sub(1, scol) .. new[1]
    new[#new] = new[#new] .. last:sub(ecol + 1)
    A.nvim_buf_set_lines(b, srow, erow + 1, false, new)
  end

  function A.nvim_buf_get_name(b)
    b = u.buf(b)
    local name = F.bufname(b)
    if name == '' then
      return ''
    end
    return F.fnamemodify(name, ':p')
  end

  function A.nvim_buf_set_name(b, name)
    b = u.buf(b)
    local cur = F.bufnr('%')
    if b == cur then
      host.exec('noautocmd file ' .. F.fnameescape(name))
    else
      host.exec('noautocmd keepalt keepjumps buffer ' .. b)
      local ok, e = pcall(host.exec, 'noautocmd file ' .. F.fnameescape(name))
      host.exec('noautocmd keepalt keepjumps buffer ' .. cur)
      if not ok then
        error(e, 0)
      end
    end
  end

  function A.nvim_buf_get_changedtick(b)
    return F.getbufvar(u.buf(b), 'changedtick')
  end

  function A.nvim_buf_delete(b, opts)
    b = u.buf(b)
    opts = opts or {}
    local cmd = opts.unload and 'bunload' or 'bwipeout'
    if opts.force then
      cmd = cmd .. '!'
    end
    host.exec(cmd .. ' ' .. b)
  end

  function A.nvim_create_buf(listed, scratch)
    local b = F.bufadd('')
    F.bufload(b)
    F.setbufvar(b, '&buflisted', listed and 1 or 0)
    if scratch then
      F.setbufvar(b, '&buftype', 'nofile')
      F.setbufvar(b, '&bufhidden', 'hide')
      F.setbufvar(b, '&swapfile', 0)
    end
    return b
  end

  function A.nvim_buf_call(b, fn)
    b = u.buf(b)
    local cur = F.bufnr('%')
    if b == cur then
      return fn()
    end
    local wins = F.win_findbuf(b)
    if #wins > 0 then
      return u.in_win(wins[1], fn)
    end
    host.exec('noautocmd keepalt keepjumps buffer ' .. b)
    local ok, res = pcall(fn)
    host.exec('noautocmd keepalt keepjumps buffer ' .. cur)
    if not ok then
      error(res, 0)
    end
    return res
  end

  function A.nvim_buf_get_mark(b, name)
    b = u.buf(b)
    local pos = F.getpos("'" .. name)
    return { pos[2], pos[3] - 1 }
  end

  function A.nvim_buf_get_var(b, name)
    local b_ = u.buf(b)
    local v = F.getbufvar(b_, name, MISSING)
    if v == MISSING then
      error('Key not found: ' .. name, 2)
    end
    return v
  end

  function A.nvim_buf_set_var(b, name, value)
    F.setbufvar(u.buf(b), name, value)
  end

  function A.nvim_buf_del_var(b, name)
    host.exec(string.format('call remove(getbufvar(%d, ""), %s)', u.buf(b), u.vstr(name)))
  end

  function A.nvim_buf_get_option(b, name)
    return A.nvim_get_option_value(name, { buf = u.buf(b) })
  end

  function A.nvim_buf_set_option(b, name, v)
    return A.nvim_set_option_value(name, v, { buf = u.buf(b) })
  end

  function A.nvim_buf_get_offset(b, index)
    b = u.buf(b)
    local n = u.linecount(b)
    if index < 0 or index > n then
      error('Index out of bounds', 2)
    end
    local off = 0
    local lines = F.getbufline(b, 1, index)
    for _, l in ipairs(lines) do
      off = off + #l + 1
    end
    return off
  end
end
