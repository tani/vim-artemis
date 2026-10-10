-- Plugin smoke test: require + setup() each listed module and report errors.
-- env: ARTEMIS_ROOT, SMOKE_PLUGINS (comma-separated plugin dirs),
--      SMOKE_MODULES (comma-separated "module" or "module:setup-call"), ARTEMIS_OUT
local root = os.getenv('ARTEMIS_ROOT')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
require('artemis.inject').setup()
for d in (os.getenv('SMOKE_PLUGINS') or ''):gmatch('[^,]+') do
  package.path = d .. '/lua/?.lua;' .. d .. '/lua/?/init.lua;' .. package.path
  vim.cmd('set rtp+=' .. d)
end

local lines = {}
for m in (os.getenv('SMOKE_MODULES') or ''):gmatch('[^,]+') do
  local mod, setup = m:match('^([^:!]+)[:!]?(.*)$')
  local nosetup = m:find('!', 1, true) ~= nil
  local ok, res = xpcall(function() return require(mod) end, debug.traceback)
  if not ok then
    lines[#lines + 1] = 'FAIL require ' .. mod .. '\n  ' .. tostring(res):gsub('\n', '\n  ')
  else
    if not nosetup and (setup ~= '' or (type(res) == 'table' and type(res.setup) == 'function')) then
      local ok2, err = xpcall(function()
        if setup ~= '' then loadstring('return ' .. setup)()(res) else res.setup() end
      end, debug.traceback)
      lines[#lines + 1] = (ok2 and 'ok   ' or 'FAIL setup ') .. mod .. (ok2 and '' or ('\n  ' .. tostring(err):gsub('\n', '\n  ')))
    else
      lines[#lines + 1] = 'ok   require ' .. mod
    end
  end
end
local f = assert(io.open(os.getenv("ARTEMIS_OUT"), "w"))
f:write(table.concat(lines, '\n') .. '\n')
f:close()
