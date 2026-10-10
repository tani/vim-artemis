# Vendored third-party code

`lua/artemis/vendor/nvim/*.lua` are copied from Neovim v0.10.4
(`runtime/lua/vim/`), unmodified:

- `shared.lua`, `iter.lua`, `F.lua`, `version.lua`, `uri.lua`
  — Apache License 2.0 (see `nvim/LICENSE`), Copyright Neovim contributors.
- `inspect.lua` — MIT License, Copyright (c) 2013 Enrique García Cota
  (the license text is embedded in the file).

Do not edit these files; compatibility adjustments live in `lua/artemis/`.
To update, re-run `scripts/vendor.sh`.
