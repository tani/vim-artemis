-- Minimal spec runner usable on both Vim (`vim -es`) and Neovim (`nvim -l`).
-- Usage: see test/run.sh
local root = vim.env and vim.env.ARTEMIS_ROOT or os.getenv('ARTEMIS_ROOT')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path

local lines = {}
local function out(s) lines[#lines + 1] = s end

require('artemis.inject').setup()

local pass, fail = 0, 0
local current = ''
_G.describe = function(name, fn) current = name; fn() end
_G.it = function(name, fn)
  local ok, err = xpcall(fn, function(e) return tostring(e) end)
  if ok then
    pass = pass + 1
  else
    fail = fail + 1
    out(string.format('FAIL %s > %s\n     %s', current, name, err))
  end
end
local function eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error((msg and (msg .. ': ') or '') .. 'expected ' .. vim.inspect(b) .. ', got ' .. vim.inspect(a), 2)
  end
end
_G.eq = eq

local specs = {}
for f in (os.getenv('ARTEMIS_SPECS') or ''):gmatch('[^,]+') do specs[#specs + 1] = f end
for _, f in ipairs(specs) do
  local ok, err = pcall(dofile, f)
  if not ok then fail = fail + 1; out('ERROR loading ' .. f .. ': ' .. tostring(err)) end
end
out(string.format('%s: %d passed, %d failed', (vim.fn.has('nvim') == 1) and 'nvim' or 'vim', pass, fail))
local f = assert(io.open(os.getenv('ARTEMIS_OUT'), 'w'))
f:write(table.concat(lines, '\n') .. '\n')
f:close()
_G.__artemis_failed = fail
