local root = os.getenv('ARTEMIS_ROOT')
package.path = root .. '/lua/?.lua;' .. root .. '/lua/?/init.lua;' .. package.path
require('artemis.inject').setup()
local pdir = os.getenv('SMOKE_PLUGINS')
package.path = pdir .. '/lua/?.lua;' .. pdir .. '/lua/?/init.lua;' .. package.path
local out = {}
local ok, err = xpcall(function()
  local Job = require('plenary.job')
  local res = Job:new({ command = 'echo', args = { 'plenary', 'works' } }):sync()
  out[#out + 1] = 'sync: ' .. vim.inspect(res)
  local job = Job:new({ command = 'sh', args = { '-c', 'cat; exit 2' }, writer = 'abc' })
  local r2 = job:sync()
  out[#out + 1] = 'cat: ' .. vim.inspect(r2) .. ' code=' .. tostring(job.code)
  local done = false
  Job:new({ command = 'echo', args = { 'async' }, on_exit = function(j, code) done = true end }):start()
  out[#out + 1] = 'async finished: ' .. tostring(vim.wait(3000, function() return done end, 10))
  local a = require('plenary.async')
  local fut
  a.run(function() a.util.sleep(10); fut = 'slept' end)
  out[#out + 1] = 'async lib: ' .. tostring(vim.wait(3000, function() return fut ~= nil end, 10)) .. ' ' .. tostring(fut)
end, debug.traceback)
if not ok then out[#out + 1] = 'ERROR ' .. tostring(err) end
local f = io.open(os.getenv('ARTEMIS_OUT'), 'w')
f:write(table.concat(out, '\n') .. '\n')
f:close()
