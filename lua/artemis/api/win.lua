-- vim.api window and tabpage functions.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy
local MISSING = '__artemis_missing__'

local function wininfo(win)
  return host.eval(string.format('getwininfo(%d)[0]', win))
end

return function(A)
  function A.nvim_get_current_win()
    return F.win_getid()
  end

  function A.nvim_set_current_win(w)
    w = u.win(w)
    if F.win_gotoid(w) == 0 then
      error('Failed to switch to window ' .. w, 2)
    end
  end

  function A.nvim_list_wins()
    local out = {}
    for _, info in ipairs(F.getwininfo()) do
      out[#out + 1] = info.winid
    end
    return out
  end

  function A.nvim_win_is_valid(w)
    return type(w) == 'number' and F.win_id2win(w) > 0
  end

  function A.nvim_win_get_buf(w)
    return F.winbufnr(u.win(w))
  end

  function A.nvim_win_set_buf(w, b)
    w = u.win(w)
    b = u.buf(b)
    u.in_win(w, function()
      host.exec('buffer ' .. b)
    end)
  end

  function A.nvim_win_get_cursor(w)
    w = u.win(w)
    return { F.line('.', w), F.col('.', w) - 1 }
  end

  function A.nvim_win_set_cursor(w, pos)
    w = u.win(w)
    u.in_win(w, function()
      F.cursor(pos[1], pos[2] + 1)
    end)
  end

  function A.nvim_win_get_height(w)
    return host.eval(string.format('getwininfo(%d)[0].height', u.win(w)))
  end

  function A.nvim_win_get_width(w)
    return host.eval(string.format('getwininfo(%d)[0].width', u.win(w)))
  end

  function A.nvim_win_set_height(w, h)
    u.in_win(u.win(w), function()
      host.exec('resize ' .. h)
    end)
  end

  function A.nvim_win_set_width(w, n)
    u.in_win(u.win(w), function()
      host.exec('vertical resize ' .. n)
    end)
  end

  function A.nvim_win_get_position(w)
    w = u.win(w)
    local row = host.eval(string.format('getwininfo(%d)[0].winrow', w))
    local col = host.eval(string.format('getwininfo(%d)[0].wincol', w))
    return { row - 1, col - 1 }
  end

  function A.nvim_win_get_number(w)
    return F.win_id2win(u.win(w))
  end

  function A.nvim_win_get_tabpage(w)
    w = u.win(w)
    return F.win_id2tabwin(w)[1]
  end

  function A.nvim_win_close(w, force)
    w = u.win(w)
    u.in_win(w, function()
      host.exec(force and 'close!' or 'close')
    end)
  end

  function A.nvim_win_hide(w)
    A.nvim_win_close(w, false)
  end

  function A.nvim_win_call(w, fn)
    return u.in_win(u.win(w), fn)
  end

  function A.nvim_win_get_var(w, name)
    local v = F.getwinvar(u.win(w), name, MISSING)
    if v == MISSING then
      error('Key not found: ' .. name, 2)
    end
    return v
  end

  function A.nvim_win_set_var(w, name, value)
    F.setwinvar(u.win(w), name, value)
  end

  function A.nvim_win_del_var(w, name)
    host.exec(string.format('call remove(getwinvar(%d, ""), %s)', u.win(w), u.vstr(name)))
  end

  function A.nvim_win_get_option(w, name)
    return A.nvim_get_option_value(name, { win = u.win(w) })
  end

  function A.nvim_win_set_option(w, name, v)
    return A.nvim_set_option_value(name, v, { win = u.win(w) })
  end

  -- tabpages (handle = tab number)
  function A.nvim_get_current_tabpage()
    return F.tabpagenr()
  end

  function A.nvim_set_current_tabpage(t)
    host.exec('tabnext ' .. u.tab(t))
  end

  function A.nvim_list_tabpages()
    local out = {}
    for i = 1, F.tabpagenr('$') do
      out[i] = i
    end
    return out
  end

  function A.nvim_tabpage_is_valid(t)
    return type(t) == 'number' and t >= 1 and t <= F.tabpagenr('$')
  end

  function A.nvim_tabpage_get_number(t)
    return u.tab(t)
  end

  function A.nvim_tabpage_list_wins(t)
    t = u.tab(t)
    local out = {}
    for _, info in ipairs(F.gettabinfo(t)[1].windows) do
      out[#out + 1] = info
    end
    return out
  end

  function A.nvim_tabpage_get_win(t)
    t = u.tab(t)
    return F.win_getid(F.tabpagewinnr(t), t)
  end
end
