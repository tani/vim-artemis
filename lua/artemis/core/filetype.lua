-- vim.filetype on Vim: match() delegates to Vim's own filetype detection
-- (run in a scratch buffer); add() registers user rules consulted first.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F = u.F

local M = {}
local rules = { extension = {}, filename = {}, pattern = {} }

function M.add(spec)
  for kind in pairs(rules) do
    for k, v in pairs(spec[kind] or {}) do
      rules[kind][k] = v
    end
  end
end

local function resolve(v, path, bufnr)
  if type(v) == 'function' then
    return v(path, bufnr)
  elseif type(v) == 'table' then
    return resolve(v[1], path, bufnr)
  end
  return v
end

function M.match(args)
  args = args or {}
  local name = args.filename
  if args.buf and not name then
    name = F.bufname(args.buf == 0 and F.bufnr('%') or args.buf)
  end
  if not name or name == '' then
    return nil
  end
  local base = name:match('[^/]+$') or name
  if rules.filename[name] or rules.filename[base] then
    return resolve(rules.filename[name] or rules.filename[base], name, args.buf)
  end
  for pat, v in pairs(rules.pattern) do
    if name:match(pat) then
      return resolve(v, name, args.buf)
    end
  end
  local ext = base:match('%.([^.]+)$')
  if ext and rules.extension[ext] then
    return resolve(rules.extension[ext], name, args.buf)
  end
  -- Vim's detection, in a throwaway buffer (enabling detection if it is off, as it
  -- always is in Neovim)
  local was_on = F.exists('#filetypedetect') ~= 0
  if not was_on then
    host.exec('filetype on')
  end
  local buf = F.bufadd('')
  F.bufload(buf)
  local ft
  local cur = F.bufnr('%')
  local ok, perr = pcall(function()
    vim.api.nvim_buf_call(buf, function()
      host.exec('noautocmd file ' .. F.fnameescape(name))
      if args.contents then
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, args.contents)
      end
      host.exec('silent! doautocmd filetypedetect BufRead ' .. F.fnameescape(name))
      ft = vim.bo[buf].filetype
    end)
  end)
  pcall(host.exec, 'silent! bwipeout! ' .. buf)
  if not ok and os.getenv('ARTEMIS_DEBUG') then
    print(perr)
  end
  if ok and ft and ft ~= '' then
    return ft
  end
  return nil
end

function M.get_option(ft, option)
  return vim.api.nvim_get_option_value(option, {})
end

return M
