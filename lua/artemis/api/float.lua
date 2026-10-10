-- Floating windows on Vim popup windows (tier B).
--
-- Supported: relative = editor/win/cursor, anchor, width/height, border
-- (named styles or char tables), title, zindex, hide, `split` windows.
-- Not supported: *entering* a float (Vim cannot enter popup windows);
-- `enter = true` opens the popup but keeps the current window, and warns once.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F = u.F

local M = {}

local floats = {} -- popup id -> normalized config

local borders = {
  single = { '─', '│', '─', '│', '┌', '┐', '┘', '└' },
  double = { '═', '║', '═', '║', '╔', '╗', '╝', '╚' },
  rounded = { '─', '│', '─', '│', '╭', '╮', '╯', '╰' },
  solid = { ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ' },
}

local warned
function M.warn_enter()
  if not warned then
    warned = true
    vim.notify(
      'artemis: Vim cannot enter floating (popup) windows; the current window is unchanged',
      vim.log.levels.WARN
    )
  end
end

local function ensure_hl()
  local defs = {
    { name = 'NormalFloat', linksto = 'Pmenu', default = true },
    { name = 'FloatBorder', linksto = 'NormalFloat', default = true },
    { name = 'FloatTitle', linksto = 'Title', default = true },
    { name = 'FloatShadow', linksto = 'Normal', default = true },
  }
  F.hlset(defs)
end

local function border_chars(border)
  if type(border) == 'string' then
    return borders[border]
  elseif type(border) == 'table' then
    local chars = {}
    for i, c in ipairs(border) do
      chars[i] = type(c) == 'table' and c[1] or c
    end
    if #chars == 1 then
      chars = { chars[1], chars[1], chars[1], chars[1], chars[1], chars[1], chars[1], chars[1] }
    elseif #chars == 2 then
      chars = { chars[2], chars[1], chars[2], chars[1], chars[2], chars[2], chars[2], chars[2] }
    end
    -- Neovim order: tl t tr r br b bl l  ->  Vim: t r b l tl tr br bl
    if #chars == 8 then
      return { chars[2], chars[4], chars[6], chars[8], chars[1], chars[3], chars[5], chars[7] }
    end
  end
  return nil
end

local anchors = { NW = 'topleft', NE = 'topright', SW = 'botleft', SE = 'botright' }

local function to_popup(cfg)
  local o = { zindex = cfg.zindex or 50, highlight = 'NormalFloat', wrap = true }
  local rel = cfg.relative or 'editor'
  local row, col = cfg.row or 0, cfg.col or 0
  local sr, sc = 1, 1
  if cfg.bufpos then
    local win = (cfg.win and cfg.win ~= 0) and cfg.win or F.win_getid()
    local p = F.screenpos(win, cfg.bufpos[1] + 1, cfg.bufpos[2] + 1)
    sr, sc = p.row, p.col
  elseif rel == 'win' then
    local win = (cfg.win and cfg.win ~= 0) and cfg.win or F.win_getid()
    local info = F.getwininfo(win)[1]
    sr, sc = info.winrow, info.wincol
  elseif rel == 'cursor' then
    local p = F.screenpos(F.win_getid(), F.line('.'), F.col('.'))
    sr, sc = p.row, p.col
  end
  o.line = sr + row
  o.col = sc + col
  o.pos = anchors[cfg.anchor or 'NW'] or 'topleft'
  if cfg.width then
    o.minwidth, o.maxwidth = cfg.width, cfg.width
  end
  if cfg.height then
    o.minheight, o.maxheight = cfg.height, cfg.height
  end
  local chars = cfg.border and cfg.border ~= 'none' and cfg.border ~= 'shadow' and border_chars(cfg.border)
  if chars then
    o.border = { 1, 1, 1, 1 }
    o.borderchars = chars
    o.borderhighlight = { 'FloatBorder' }
    if cfg.title then
      local t = cfg.title
      if type(t) == 'table' then
        local parts = {}
        for _, chunk in ipairs(t) do
          parts[#parts + 1] = type(chunk) == 'table' and chunk[1] or chunk
        end
        t = table.concat(parts)
      end
      o.title = t
    end
  end
  return o
end

function M.open(A, buf, enter, cfg)
  cfg = cfg or {}
  buf = u.buf(buf)
  if cfg.split or (cfg.relative == nil and cfg.win ~= nil) then
    -- Regular split window (Neovim 0.10: split = left/right/above/below).
    local dir = cfg.split or 'below'
    local cmds = { left = 'leftabove vsplit', right = 'rightbelow vsplit', above = 'leftabove split', below = 'rightbelow split' }
    local function do_split()
      host.exec(cmds[dir] or 'split')
      host.exec('buffer ' .. buf)
      return F.win_getid()
    end
    local ref = cfg.win and cfg.win ~= 0 and cfg.win or F.win_getid()
    local cur = F.win_getid()
    F.win_gotoid(ref)
    local newwin = do_split()
    if not enter and F.win_id2win(cur) ~= 0 then
      F.win_gotoid(cur)
    end
    return newwin
  end
  if cfg.relative == nil then
    error("Invalid 'relative': must be provided for floating windows", 2)
  end
  ensure_hl()
  local o = to_popup(cfg)
  o.callback = function(id)
    floats[id] = nil
  end
  local id = F.popup_create(buf, o)
  floats[id] = vim.deepcopy(cfg)
  if cfg.hide then
    F.popup_hide(id)
  end
  if enter then
    M.warn_enter()
  end
  return id
end

function M.get_config(w)
  local cfg = floats[w]
  if not cfg then
    local info = F.getwininfo(w)[1] or {}
    return {
      relative = '',
      external = false,
      focusable = true,
      width = info.width,
      height = info.height,
      row = 0,
      col = 0,
    }
  end
  local pos = F.popup_getpos(w)
  local out = vim.deepcopy(cfg)
  out.relative = cfg.relative or 'editor'
  out.external = false
  out.focusable = cfg.focusable ~= false
  out.zindex = cfg.zindex or 50
  out.width = pos.core_width
  out.height = pos.core_height
  out.hide = F.popup_getoptions(w).hidden == 1 and true or nil
  return out
end

function M.set_config(w, cfg)
  local cur = floats[w]
  if not cur then
    if cfg.relative and cfg.relative ~= '' then
      error('artemis: cannot turn a regular window into a floating window on Vim', 2)
    end
    return
  end
  for k, v in pairs(cfg) do
    cur[k] = v
  end
  local o = to_popup(cur)
  local pos = { line = o.line, col = o.col, pos = o.pos, minwidth = o.minwidth, maxwidth = o.maxwidth,
    minheight = o.minheight, maxheight = o.maxheight }
  F.popup_move(w, pos)
  F.popup_setoptions(w, { zindex = o.zindex, title = o.title or '' })
  if cfg.hide == true then
    F.popup_hide(w)
  elseif cfg.hide == false then
    F.popup_show(w)
  end
end

return M
