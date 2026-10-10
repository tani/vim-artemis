-- Highlight groups that Neovim always defines but Vim does not. Defined as
-- `default link`s to the closest Vim group so colorschemes can override them.
local M = {}

local links = {
  { 'Whitespace', 'NonText' },
  { 'WinSeparator', 'VertSplit' },
  { 'WinBar', 'StatusLine' },
  { 'WinBarNC', 'StatusLineNC' },
  { 'NormalFloat', 'Pmenu' },
  { 'FloatBorder', 'NormalFloat' },
  { 'FloatTitle', 'Title' },
  { 'FloatFooter', 'FloatTitle' },
  { 'FloatShadow', 'Normal' },
  { 'FloatShadowThrough', 'Normal' },
  { 'MsgArea', 'Normal' },
  { 'MsgSeparator', 'StatusLine' },
  { 'NvimInternalError', 'ErrorMsg' },
  { 'CursorLineSign', 'SignColumn' },
  { 'CursorLineFold', 'FoldColumn' },
  { 'Added', 'DiffAdd' },
  { 'Changed', 'DiffChange' },
  { 'Removed', 'DiffDelete' },
  { 'DiagnosticError', 'ErrorMsg' },
  { 'DiagnosticWarn', 'WarningMsg' },
  { 'DiagnosticInfo', 'Normal' },
  { 'DiagnosticHint', 'Normal' },
  { 'DiagnosticOk', 'Normal' },
  { 'DiagnosticUnderlineError', 'SpellBad' },
  { 'DiagnosticUnderlineWarn', 'SpellCap' },
  { 'DiagnosticUnderlineInfo', 'SpellLocal' },
  { 'DiagnosticUnderlineHint', 'SpellRare' },
  { 'DiagnosticVirtualTextError', 'DiagnosticError' },
  { 'DiagnosticVirtualTextWarn', 'DiagnosticWarn' },
  { 'DiagnosticVirtualTextInfo', 'DiagnosticInfo' },
  { 'DiagnosticVirtualTextHint', 'DiagnosticHint' },
  { 'DiagnosticSignError', 'DiagnosticError' },
  { 'DiagnosticSignWarn', 'DiagnosticWarn' },
  { 'DiagnosticSignInfo', 'DiagnosticInfo' },
  { 'DiagnosticSignHint', 'DiagnosticHint' },
  { 'LspReferenceText', 'Visual' },
  { 'LspReferenceRead', 'LspReferenceText' },
  { 'LspReferenceWrite', 'LspReferenceText' },
  { 'LspCodeLens', 'NonText' },
  { 'LspSignatureActiveParameter', 'Visual' },
  { 'Substitute', 'Search' },
}

function M.setup()
  local defs = {}
  for _, l in ipairs(links) do
    defs[#defs + 1] = { name = l[1], linksto = l[2], default = true }
  end
  vim.fn.hlset(defs)
end

return M
