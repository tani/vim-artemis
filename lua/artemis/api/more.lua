-- Remaining small vim.api functions.
local host = require('artemis.core.host')
local convert = require('artemis.core.convert')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy

return function(A)
  function A.nvim_exec_lua(code, args)
    local chunk, err = loadstring(code)
    if not chunk then
      error(err, 0)
    end
    local unpack = unpack or table.unpack
    return chunk(unpack(args or {}, 1, #(args or {})))
  end

  function A.nvim_notify(msg, level, opts)
    vim.notify(msg, level, opts)
  end

  function A.nvim_set_current_dir(dir)
    host.exec('cd ' .. F.fnameescape(dir))
  end

  function A.nvim_paste(data, crlf, phase)
    local lines = vim.split(data, '\n', { plain = true })
    if crlf then
      for i, l in ipairs(lines) do
        lines[i] = l:gsub('\r$', '')
      end
    end
    A.nvim_put(lines, 'c', true, true)
    return true
  end

  -- marks
  function A.nvim_buf_set_mark(buf, name, line, col, opts)
    buf = u.buf(buf)
    return F.setpos("'" .. name, { buf, line, col + 1, 0 }) == 0
  end
  function A.nvim_buf_del_mark(buf, name)
    host.exec('delmarks ' .. name)
    return true
  end
  function A.nvim_get_mark(name, opts)
    local pos = F.getpos("'" .. name)
    return { pos[2], pos[3] - 1, pos[1], F.bufname(pos[1]) }
  end
  function A.nvim_del_mark(name)
    host.exec('delmarks ' .. name)
    return true
  end

  function A.nvim_get_option_info(name)
    local i = A.nvim_get_option_info2(name, {})
    return i
  end

  function A.nvim_get_commands(opts)
    -- Only user-defined commands are available; parsed from :command output.
    local out = {}
    local text = host.exec('command')
    for line in text:gmatch('[^\n]+') do
      local name = line:match('^[!%s"b]*%s+(%u[%w_]*)%s')
      if name and name ~= 'Name' then
        out[name] = { name = name, definition = '', script_id = 0, bang = false, bar = false,
          register = false, nargs = '0', keepscript = false }
      end
    end
    return out
  end

  function A.nvim_get_color_by_name(name)
    if name:match('^#%x%x%x%x%x%x$') then
      return tonumber(name:sub(2), 16)
    end
    return require('artemis.core.colors')[name:lower()] or -1
  end

  function A.nvim_get_color_map()
    local out = {}
    for k, v in pairs(require('artemis.core.colors')) do
      out[k] = v
    end
    return out
  end

  -- buffer change notifications on top of listener_add()
  local attached = {} -- buf -> { handle, opts }
  function A.nvim_buf_attach(buf, send_buffer, opts)
    buf = u.buf(buf)
    opts = opts or {}
    if attached[buf] then
      return false
    end
    local rec = { opts = opts }
    local function on_change(bufnr, start, finish, added, changes)
      -- Vim: lines [start, finish) (1-based) replaced by `added`-shifted range.
      local first = start - 1
      local last_old = finish - 1
      local last_new = last_old + added
      local tick = F.getbufvar(bufnr, 'changedtick')
      if opts.on_lines then
        local r = opts.on_lines('lines', bufnr, tick, first, last_old, last_new, 0)
        if r == true then
          A.nvim_buf_detach(bufnr)
        end
      end
    end
    rec.handle = F.listener_add(function(bufnr, start, finish, added, changes)
      on_change(bufnr, start, finish, added, changes)
    end, buf)
    attached[buf] = rec
    if opts.on_detach then
      -- Detach notification when the buffer is wiped.
      A.nvim_create_autocmd('BufWipeout', {
        buffer = buf,
        once = true,
        callback = function()
          if attached[buf] then
            attached[buf] = nil
            opts.on_detach('detach', buf)
          end
        end,
      })
    end
    return true
  end

  -- Vim calls listeners lazily (before redraw); Neovim calls on_lines
  -- synchronously, so flush right after our own edits.
  function A._after_edit()
    if next(attached) ~= nil then
      F.listener_flush()
    end
  end

  function A.nvim_buf_detach(buf)
    buf = u.buf(buf)
    local rec = attached[buf]
    if not rec then
      return false
    end
    F.listener_remove(rec.handle)
    attached[buf] = nil
    if rec.opts.on_detach then
      rec.opts.on_detach('detach', buf)
    end
    return true
  end
end
