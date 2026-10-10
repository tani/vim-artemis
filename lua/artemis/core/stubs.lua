-- Graceful-degradation stubs for subsystems that cannot be emulated on Vim
-- (tier C): treesitter, lsp, diagnostic. Plugins that probe for them with
-- pcall()/get_clients() see "nothing available" instead of crashing.
local M = {}

local function unsupported(name)
  return function()
    error('artemis: ' .. name .. ' is not supported on Vim', 2)
  end
end

function M.setup()
  if vim.treesitter == nil then
    local ts = {
      get_parser = unsupported('vim.treesitter.get_parser'),
      get_string_parser = unsupported('vim.treesitter.get_string_parser'),
      get_node = function() return nil end,
      get_captures_at_pos = function() return {} end,
      get_captures_at_cursor = function() return {} end,
      start = unsupported('vim.treesitter.start'),
      stop = function() end,
      is_ancestor = function() return false end,
      language = {
        get_lang = function(ft) return ft end,
        add = unsupported('vim.treesitter.language.add'),
        register = function() end,
      },
      query = {
        get = function() return nil end,
        parse = unsupported('vim.treesitter.query.parse'),
        get_query = function() return nil end,
      },
      highlighter = { active = {} },
    }
    vim.treesitter = ts
    package.preload['vim.treesitter'] = function() return ts end
  end

  if vim.lsp == nil then
    local lsp = {
      get_clients = function() return {} end,
      get_active_clients = function() return {} end,
      get_client_by_id = function() return nil end,
      buf = setmetatable({}, { __index = function() return unsupported('vim.lsp.buf') end }),
      util = setmetatable({}, { __index = function() return unsupported('vim.lsp.util') end }),
      protocol = { Methods = {}, CompletionItemKind = {}, SymbolKind = {} },
      handlers = {},
      start = unsupported('vim.lsp.start'),
      enable = unsupported('vim.lsp.enable'),
      config = {},
    }
    vim.lsp = lsp
    package.preload['vim.lsp'] = function() return lsp end
  end

  if vim.diagnostic == nil then
    local severity = { ERROR = 1, WARN = 2, INFO = 3, HINT = 4, 'ERROR', 'WARN', 'INFO', 'HINT' }
    local d = {
      severity = severity,
      get = function() return {} end,
      count = function() return {} end,
      config = function() return {} end,
      set = function() end,
      reset = function() end,
      hide = function() end,
      show = function() end,
      enable = function() end,
      disable = function() end,
      is_enabled = function() return false end,
      get_namespace = function() return {} end,
      get_namespaces = function() return {} end,
      goto_next = function() end,
      goto_prev = function() end,
      open_float = function() end,
      match = function() return nil end,
      fromqflist = function() return {} end,
      toqflist = function() return {} end,
    }
    vim.diagnostic = d
    package.preload['vim.diagnostic'] = function() return d end
  end
end

return M
