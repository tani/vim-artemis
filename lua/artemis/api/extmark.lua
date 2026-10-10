-- vim.api extmarks / highlights on Vim text properties (tier B).
--
-- Supported: position tracking, end_row/end_col ranges, hl_group, priority,
-- gravity, virt_text (eol / inline / right_align), virt_lines, clear/get/del.
-- Differences: a mark whose whole range is deleted disappears (Neovim keeps
-- it); overlay virt_text is approximated as inline; sign_text, line_hl_group,
-- number_hl_group, conceal and spell are ignored.
local host = require('artemis.core.host')
local u = require('artemis.api.util')
local F, truthy = u.F, u.truthy

local ns_types = {}      -- ns -> { typename = true }
local created = {}       -- typename -> true
local by_prop = {}       -- buf -> { [prop_id] = { ns = , id = } }
local by_ext = {}        -- buf -> { [ns] = { [ext_id] = prop_id } }
local next_prop = 0
local next_ext = {}      -- ns -> counter

local function tname(ns, hl, prio, rg, erg)
  return string.format('artemis_%d_%s_%d_%d%d', ns, hl or '', prio, rg and 1 or 0, erg and 1 or 0)
end

local function ensure_type(ns, hl, prio, rg, erg)
  local name = tname(ns, hl, prio, rg, erg)
  if not created[name] then
    local def = {
      priority = prio,
      start_incl = not rg and 1 or 0,
      end_incl = erg and 1 or 0,
      combine = 1,
    }
    if hl then
      def.highlight = hl
    end
    F.prop_type_add(name, def)
    created[name] = true
    ns_types[ns] = ns_types[ns] or {}
    ns_types[ns][name] = true
  end
  return name
end

local function ns_of_type(name)
  return tonumber(name:match('^artemis_(%d+)_'))
end

local function table_for(tbl, buf)
  tbl[buf] = tbl[buf] or {}
  return tbl[buf]
end

local function chunk_hl(chunk)
  local hl = chunk[2]
  if type(hl) == 'table' then
    hl = hl[1]
  end
  return hl
end


--- Create the text properties for one extmark.
local function place(buf, desc, pid, row, col, erow, ecol, lenient)
  local ns, opts = desc.ns, desc.opts
  local prio = opts.priority or 4096
  local rg = opts.right_gravity ~= false
  local erg = opts.end_right_gravity == true
  local base = { id = pid, bufnr = buf }
  local function add(lnum, c, propopts)
    local pe = {}
    for k, v in pairs(base) do pe[k] = v end
    for k, v in pairs(propopts) do pe[k] = v end
    F.prop_add(lnum, c, pe)
  end
  if opts.hl_group or erow or ecol or not (opts.virt_text or opts.virt_lines) then
    local name = ensure_type(ns, opts.hl_group, prio, rg, erg)
    local p = { type = name }
    if erow or ecol then
      local er = erow or row
      local ec = ecol or col
      if lenient then
        local last = F.getbufline(buf, er + 1, er + 1)[1] or ''
        ec = math.min(ec, #last)
      end
      p.end_lnum = er + 1
      p.end_col = ec + 1
    else
      p.length = 0
    end
    add(row + 1, col + 1, p)
  end
  if opts.virt_text then
    local pos = opts.virt_text_pos or 'eol'
    for _, chunk in ipairs(opts.virt_text) do
      local name = ensure_type(ns, chunk_hl(chunk), prio, rg, erg)
      local p = { type = name, text = chunk[1], text_wrap = 'truncate' }
      if pos == 'eol' then
        p.text_align = 'after'
        add(row + 1, 0, p)
      elseif pos == 'right_align' then
        p.text_align = 'right'
        add(row + 1, 0, p)
      else
        add(row + 1, col + 1, p)
      end
    end
  end
  if opts.virt_lines then
    for _, vl in ipairs(opts.virt_lines) do
      local text, hl = {}, nil
      for _, chunk in ipairs(vl) do
        text[#text + 1] = chunk[1]
        hl = hl or chunk_hl(chunk)
      end
      local name = ensure_type(ns, hl, prio, rg, erg)
      add(row + 1, 0, {
        type = name,
        text = table.concat(text),
        text_align = opts.virt_lines_above and 'above' or 'below',
      })
    end
  end
end

return function(A)
  function A.nvim_buf_set_extmark(buf, ns, line, col, opts)
    buf = u.buf(buf)
    opts = opts or {}
    local n = u.linecount(buf)
    if line < 0 or line >= n then
      if opts.strict == false then
        line = math.max(0, math.min(line, n - 1))
      else
        error('Invalid \'line\': out of range', 2)
      end
    end
    local text = F.getbufline(buf, line + 1, line + 1)[1] or ''
    if col > #text then
      if opts.strict == false then
        col = #text
      else
        error('Invalid \'col\': out of range', 2)
      end
    end
    local exts = table_for(by_ext, buf)
    exts[ns] = exts[ns] or {}
    local id = opts.id
    if id then
      local old = exts[ns][id]
      if old then
        A.nvim_buf_del_extmark(buf, ns, id)
      end
    else
      next_ext[ns] = (next_ext[ns] or 0) + 1
      id = next_ext[ns]
      while exts[ns][id] do
        next_ext[ns] = next_ext[ns] + 1
        id = next_ext[ns]
      end
    end
    next_prop = next_prop + 1
    local pid = next_prop
    local desc = {
      ns = ns,
      id = id,
      opts = {
        hl_group = opts.hl_group,
        priority = opts.priority,
        right_gravity = opts.right_gravity,
        end_right_gravity = opts.end_right_gravity,
        virt_text = opts.virt_text,
        virt_text_pos = opts.virt_text_pos,
        virt_lines = opts.virt_lines,
        virt_lines_above = opts.virt_lines_above,
      },
    }
    place(buf, desc, pid, line, col, opts.end_row, opts.end_col, opts.strict == false)
    table_for(by_prop, buf)[pid] = desc
    exts[ns][id] = pid
    return id
  end

  local function find(buf, ns, id)
    local pid = by_ext[buf] and by_ext[buf][ns] and by_ext[buf][ns][id]
    if not pid then
      return nil
    end
    local r = F.prop_find({ id = pid, bufnr = buf, lnum = 1, col = 1 }, 'f')
    if type(r) ~= 'table' or not r.lnum then
      return nil, pid
    end
    return r, pid
  end

  function A.nvim_buf_get_extmark_by_id(buf, ns, id, opts)
    buf = u.buf(buf)
    local r = find(buf, ns, id)
    if not r then
      return {}
    end
    local row, col = r.lnum - 1, r.col - 1
    if opts and opts.details then
      local details = { ns_id = ns }
      if r.length and r.length > 0 then
        details.end_row = r.lnum - 1
        details.end_col = r.col - 1 + r.length
      end
      return { row, col, details }
    end
    return { row, col }
  end

  function A.nvim_buf_del_extmark(buf, ns, id)
    buf = u.buf(buf)
    local pid = by_ext[buf] and by_ext[buf][ns] and by_ext[buf][ns][id]
    if not pid then
      return false
    end
    for name in pairs(ns_types[ns] or {}) do
      F.prop_remove({ id = pid, type = name, bufnr = buf, all = 1, both = 1 })
    end
    by_ext[buf][ns][id] = nil
    by_prop[buf][pid] = nil
    return true
  end

  function A.nvim_buf_clear_namespace(buf, ns, line_start, line_end)
    buf = u.buf(buf)
    local namespaces = {}
    if ns == -1 then
      for k in pairs(ns_types) do namespaces[#namespaces + 1] = k end
    else
      namespaces[1] = ns
    end
    local first = (line_start or 0) + 1
    local last = (line_end == nil or line_end == -1) and u.linecount(buf) or line_end
    for _, n in ipairs(namespaces) do
      for name in pairs(ns_types[n] or {}) do
        F.prop_remove({ type = name, bufnr = buf, all = 1 }, first, last)
      end
      if (line_start or 0) == 0 and (line_end == nil or line_end == -1) then
        if by_ext[buf] then by_ext[buf][n] = nil end
        if by_prop[buf] then
          for pid, rec in pairs(by_prop[buf]) do
            if rec.ns == n then by_prop[buf][pid] = nil end
          end
        end
      end
    end
  end

  function A.nvim_buf_get_extmarks(buf, ns, start, finish, opts)
    buf = u.buf(buf)
    opts = opts or {}
    local n = u.linecount(buf)
    local function pos(p, default_last)
      if type(p) == 'number' then
        if p < 0 then
          return default_last and (n - 1) or 0, default_last and math.huge or 0
        end
        return p, 0
      end
      return p[1], p[2]
    end
    local srow, scol = pos(start, false)
    local erow, ecol = pos(finish, true)
    local types = {}
    for k in pairs(ns_types) do
      if ns == -1 or k == ns then
        for name in pairs(ns_types[k]) do types[#types + 1] = name end
      end
    end
    local out = {}
    if #types == 0 then
      return out
    end
    erow = math.min(erow, n - 1)
    for row = srow, erow do
      local props = F.prop_list(row + 1, { bufnr = buf, types = types })
      for _, p in ipairs(props) do
        local rec = by_prop[buf] and by_prop[buf][p.id]
        if rec and (p.start == 1 or p.start == nil) then
          local col = p.col - 1
          if (row > srow or col >= scol) and (row < erow or col <= ecol) then
            local item = { rec.id, row, col }
            if opts.details then
              item[4] = { ns_id = rec.ns }
            end
            out[#out + 1] = item
          end
        end
      end
    end
    if opts.limit and opts.limit > 0 and #out > opts.limit then
      for i = #out, opts.limit + 1, -1 do out[i] = nil end
    end
    return out
  end

  function A.nvim_buf_add_highlight(buf, ns, hl_group, line, col_start, col_end)
    buf = u.buf(buf)
    if ns == 0 then
      ns = A.nvim_create_namespace('')
    end
    if ns < 0 then
      ns = A.nvim_create_namespace('')
    end
    local opts = { hl_group = hl_group, strict = false }
    if col_end ~= -1 then
      opts.end_row = line
      opts.end_col = col_end
    else
      opts.end_row = line
      opts.end_col = #(F.getbufline(buf, line + 1, line + 1)[1] or '')
    end
    A.nvim_buf_set_extmark(buf, ns, line, col_start, opts)
    return ns
  end

  function A.nvim_buf_clear_highlight(buf, ns, s, e)
    A.nvim_buf_clear_namespace(buf, ns, s, e)
  end


  --- Read the current extent of tracked mark `pid`: row, col, erow, ecol.
  local function read_mark(buf, pid)
    local r = F.prop_find({ id = pid, bufnr = buf, lnum = 1, col = 1 }, 'f')
    if type(r) ~= 'table' or not r.lnum then
      return nil
    end
    local row, col = r.lnum - 1, r.col - 1
    local erow, ecol = row, col + (r.length or 0)
    local cur = r
    while cur['end'] == 0 do
      cur = F.prop_find({ id = pid, bufnr = buf, lnum = cur.lnum + 1, col = 1 }, 'f')
      if type(cur) ~= 'table' or not cur.lnum then
        break
      end
      erow, ecol = cur.lnum - 1, cur.col - 1 + (cur.length or 0)
    end
    return row, col, erow, ecol
  end

  --- Snapshot marks starting on rows [srow, erow] (0-based, inclusive) so
  --- they can be re-created after the lines are rewritten.
  function A._ext_save(buf, srow, erow)
    local tracked = by_prop[buf]
    if not tracked or next(tracked) == nil then
      return nil
    end
    local types = {}
    for _, set in pairs(ns_types) do
      for name in pairs(set) do types[#types + 1] = name end
    end
    local seen, saved = {}, {}
    for row = srow, erow do
      for _, p in ipairs(F.prop_list(row + 1, { bufnr = buf, types = types })) do
        local desc = tracked[p.id]
        if desc and not seen[p.id] and (p.start == 1) then
          seen[p.id] = true
          local r, c, er, ec = read_mark(buf, p.id)
          if r then
            saved[#saved + 1] = { pid = p.id, desc = desc, row = r, col = c, erow = er, ecol = ec }
          end
        end
      end
    end
    return saved
  end

  --- Re-create saved marks; `map(row, col) -> row, col` gives new positions.
  function A._ext_restore(buf, saved, map)
    if not saved then
      return
    end
    local n = u.linecount(buf)
    for _, m in ipairs(saved) do
      for name in pairs(ns_types[m.desc.ns] or {}) do
        F.prop_remove({ id = m.pid, type = name, bufnr = buf, all = 1, both = 1 })
      end
      local r, c = map(m.row, m.col)
      local er, ec = map(m.erow, m.ecol)
      r = math.min(r, n - 1)
      local has_range = m.erow ~= m.row or m.ecol ~= m.col
      place(buf, m.desc, m.pid, r, c, has_range and er or nil, has_range and ec or nil, true)
    end
  end

  function A.nvim_set_decoration_provider() end
  function A.nvim__win_add_ns() end
  function A.nvim__win_del_ns() end
  function A.nvim_win_set_hl_ns() end
  function A.nvim_set_hl_ns() end
end
