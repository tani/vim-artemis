-- L1: install the pure-Lua parts of Neovim's `vim` namespace
-- (vim.shared / inspect / iter / F / version / uri) using the vendored copies.
--
-- On Neovim only what is missing (e.g. vim.iter on 0.9) is added; native
-- implementations are never replaced. On Vim everything is installed.
local host = require('artemis.core.host')

local M = {}

-- Minimal LuaJIT `bit` replacement: Vim's Lua is stock PUC Lua 5.1, and
-- vendored code does `require('bit')`.
local function install_bit()
  if package.loaded['bit'] or package.preload['bit'] or pcall(require, 'bit') then
    return
  end
  local bit = {}
  local MOD = 2 ^ 32
  local function norm(x)
    x = math.floor(x) % MOD
    return x
  end
  local function tosigned(x)
    if x >= 2 ^ 31 then
      return x - MOD
    end
    return x
  end
  local function op(f)
    return function(a, b, ...)
      a, b = norm(a), norm(b)
      local r, p = 0, 1
      for _ = 1, 32 do
        local x, y = a % 2, b % 2
        if f(x, y) then
          r = r + p
        end
        a, b, p = (a - x) / 2, (b - y) / 2, p * 2
      end
      if select('#', ...) > 0 then
        return bit.__fold(f, tosigned(r), ...)
      end
      return tosigned(r)
    end
  end
  bit.band = op(function(x, y) return x == 1 and y == 1 end)
  bit.bor = op(function(x, y) return x == 1 or y == 1 end)
  bit.bxor = op(function(x, y) return x ~= y end)
  function bit.bnot(a) return tosigned(MOD - 1 - norm(a)) end
  function bit.lshift(a, n) return tosigned(norm(norm(a) * 2 ^ (n % 32))) end
  function bit.rshift(a, n) return tosigned(math.floor(norm(a) / 2 ^ (n % 32))) end
  function bit.tobit(a) return tosigned(norm(a)) end
  function bit.tohex(a, n)
    n = n or 8
    local s = string.format('%08x', norm(a))
    if n < 0 then
      return s:sub(n):upper()
    end
    return s:sub(-n)
  end
  package.preload['bit'] = function() return bit end
end

local function sentinel()
  if vim.NIL == nil then
    vim.NIL = setmetatable({}, {
      __tostring = function() return 'vim.NIL' end,
    })
  end
  if vim._empty_dict_mt == nil then
    vim._empty_dict_mt = {
      __tostring = function() return 'vim.empty_dict()' end,
    }
  end
  if vim.deprecate == nil then
    -- Neovim prints a one-time warning; we stay silent.
    vim.deprecate = function() end
  end
  if vim.empty_dict == nil then
    vim.empty_dict = function()
      return setmetatable({}, vim._empty_dict_mt)
    end
  end
end

local vendor = 'artemis.vendor.nvim.'

function M.setup()
  if M._done then
    return
  end
  M._done = true
  install_bit()
  sentinel()

  if host.kind == 'vim' then
    -- shared.lua assigns into the global `vim` table as a side effect.
    require(vendor .. 'shared')
    package.preload['vim.shared'] = package.preload['vim.shared'] or function()
      return vim
    end
  end

  if vim.inspect == nil then
    vim.inspect = require(vendor .. 'inspect')
  end
  package.preload['vim.inspect'] = package.preload['vim.inspect']
    or function() return vim.inspect end

  if vim.iter == nil then
    vim.iter = require(vendor .. 'iter')
  end
  package.preload['vim.iter'] = package.preload['vim.iter']
    or function() return vim.iter end

  if vim.F == nil then
    vim.F = require(vendor .. 'F')
  end
  package.preload['vim.F'] = package.preload['vim.F'] or function() return vim.F end

  if host.kind == 'vim' then
    local version = require(vendor .. 'version')
    local native = vim.version
    vim._vim_version = native
    local function get_version()
      local v = host.eval('v:version')
      local patch = host.eval('has("patch")') and 0 or 0
      return { major = math.floor(v / 100), minor = v % 100, patch = patch }
    end
    vim.version = setmetatable(version, {
      __call = function()
        return get_version()
      end,
    })
    if vim.uri_from_fname == nil then
      local uri = require(vendor .. 'uri')
      vim.uri_from_fname = uri.uri_from_fname
      vim.uri_to_fname = uri.uri_to_fname
      vim.uri_from_bufnr = uri.uri_from_bufnr
      vim.uri_to_bufnr = uri.uri_to_bufnr
    end
  end
end

return M
