# Limitations on Vim

Tiers: **A** exact, **B** approximate (documented difference), **C** unsupported
(clear error or inert stub).

## Behavioural differences (tier B)

| Area | Difference |
|---|---|
| `vim.fn.has('nvim')` | Returns 0 on Vim on purpose; plugins then take their Vim code paths. |
| Values | `v:true`/`v:false` read as `1`/`0`; `v:null` reads as `nil`. |
| `vim.api.nvim_buf_set_extmark` | Built on text properties. A mark whose whole range is deleted disappears (Neovim keeps it). Overlay virtual text is drawn inline. `sign_text`, `line_hl_group`, `number_hl_group`, `conceal`, `spell` are ignored. Marks are carried across `nvim_buf_set_lines` / `nvim_buf_set_text`, but not across edits made through other means if the line is fully rewritten by Vim itself. |
| Floating windows | Popup windows: display only. **Vim cannot enter a popup**; `enter = true` opens the float, keeps the current window and warns once. Buffer-local keymaps inside floats do not work. |
| Autocmds | Neovim-only events (`TermOpen`, `LspAttach`, ...) are accepted and never fire. Callbacks returning `true`/`nvim_del_autocmd` disable the callback but the Vim-side autocmd entry stays. |
| Options | Neovim-only options (`statuscolumn`, `winbar`, `splitkeep`, ...) are remembered but have no effect. |
| `vim.uv` | A subset: timers, async, check/idle/prepare (10 ms ticks), synchronous fs, `os_*`, `spawn` with stdio pipes, `kill`. `fs_event`/`fs_poll` poll once per second. No sockets/tcp/udp/signals/tty. Callbacks always run on the main loop (there is no fast-event context). |
| `vim.api.nvim_buf_attach` | `on_lines` only (via listeners); `on_bytes`/`on_reload` are not emitted. |
| Window handles | Window ids are Vim window-ids; tabpage handles are tab numbers. |
| `v:lua` | Emulated by rewriting expressions (`v:lua.f(...)` -> `luaeval`) and by Funcrefs for `operatorfunc`/`completefunc`/`omnifunc`/... options. A bare `v:lua.f` outside those options is not translated. |
| Errors | Vim-level errors are raised as Lua errors with the Vim message; they are not decorated like `E5108`. |

## Unsupported (tier C)

`vim.lsp`, `vim.treesitter` and `vim.diagnostic` are inert stubs (no clients, no
parsers, no diagnostics) so that plugins can probe and degrade gracefully.
`nvim_open_term`, `nvim_ui_*`, `nvim_set_decoration_provider` (no-op),
`vim.mpack`, remote/RPC APIs, `vim.lpeg`, `vim.snippet`.

## Tips

- Load order: call `require('artemis.inject').setup()` before any plugin that
  uses `vim.api`/`vim.keymap` at require time.
- Ensure the artemis directory is on `runtimepath` (so `lua/artemis/` is found).
- The helper function `ArtemisCall()` is defined globally in Vim; it is how
  Vim errors are turned into Lua errors without leaking exceptions.
