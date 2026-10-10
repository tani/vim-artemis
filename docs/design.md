# vim-artemis v2 設計

## 1. 目標と非目標

**目標**
- 既存の Neovim Lua プラグイン(`vim.api` / `vim.fn` / `vim.keymap` / `vim.opt` 等を使うもの)を、**無改造のまま Vim(`+lua`)で動かす**。
- Vim 専用機能(popup / textprop / job / channel)を Neovim 上でも `vim.fn.*` 経由で使えるようにし、**Vim 向け Lua プラグインも Neovim で動かす**。
- 両ホストで共通に使える部分を最大化し、ホスト依存コードを小さな「ホスト層」に閉じ込める。
- 動かないものは**黙って失敗せず、明示的にエラー**にする(サポート階層を定義)。

**非目標**
- Neovim 固有の巨大サブシステム(`vim.lsp`, `vim.treesitter`, `vim.diagnostic` 完全互換、RPC/remote plugin)の再実装。
- Vim9script の Neovim 上での実行。
- Vim script プラグインが直接呼ぶ小文字グローバル関数(`popup_create()` 等)の Neovim 上での定義(Neovim は小文字始まりのユーザー関数を定義できないため不可能)。対象は **Lua から呼ばれる経路**に限る。

## 2. 現状 (v1) の設計上の問題

| 問題 | 内容 |
|---|---|
| 単一ファイル | 約500行に全機能が同居。ホスト分岐 (`has('nvim')`) が各所に散在。 |
| 文字列組み立て依存 | Vim 側は `:command` / `:map` / `:autocmd` を文字列で組み立てる。クォートや特殊キーに脆い。 |
| コールバック管理 | `_command[name]` / `_keymap[lhs]` / `_autocmd[id]` がキー衝突する(モード・バッファ違い、ローカル/グローバル違い)。解放もされない。 |
| 値変換が場当たり | `cast` は dict/list の推定のみ。`v:null` / `v:true` / Funcref / 空 dict と空 list の区別 / 数値型が未対応。 |
| 標準ライブラリ不足 | `vim.split`, `vim.tbl_*`, `vim.deepcopy`, `vim.inspect` 等を Vim 側で未提供のまま使っている。 |
| `vim` を置き換えない | 独自名前空間 `artemis` のみ。既存プラグインは `vim.api` を直接参照するので動かない。 |
| テストなし | 互換性を機械的に検証できない。 |

## 3. アーキテクチャ(レイヤー構成)

下位ほどホスト依存、上位ほど Neovim API と同一の見た目。**上位層はホストを一切知らない**のが原則。

```
┌─────────────────────────────────────────────┐
│ L5  inject / facade     vim.* を Vim に注入   │  ← プラグインから見える面
├─────────────────────────────────────────────┤
│ L4  vim.uv / vim.system / vim.schedule / ui  │  非同期・イベントループ
├─────────────────────────────────────────────┤
│ L3  vim.api (nvim_*)    階層 A/B/C で実装     │  最大の面積
├─────────────────────────────────────────────┤
│ L2  core: convert / registry / errors / has  │  値変換・コールバック表・エラー
├─────────────────────────────────────────────┤
│ L1  shared (純Lua)      vim.split, tbl_*, … │  ホスト非依存
├─────────────────────────────────────────────┤
│ L0  host                nvim | vim アダプタ   │  eval/cmd/call の最小原始操作
└─────────────────────────────────────────────┘
```

### L0 host — 最小原始操作
ホスト差を吸収する**唯一**の層。提供するのは次のみ。
`eval(expr)`, `exec(cmd)`, `call(fname, args)`, `funcref_from_lua(fn)`, `kind` (`'nvim'|'vim'`), `version`, `lua_kind` (`jit|5.1|5.3|5.4`)。
- nvim: `vim.api.nvim_eval` / `nvim_exec2` / `vim.fn`
- vim: `vim.eval` / `vim.command` / `vim.call`、Lua 関数は `luaeval()` 経由のトランポリンで呼ぶ。

### L1 shared — 純 Lua 標準ライブラリ
Neovim の `vim.shared` / `vim.iter` / `vim.inspect` 相当を**ホスト非依存の Lua として実装**: `split`, `gsplit`, `trim`, `startswith`, `endswith`, `tbl_*`, `list_*`, `deepcopy`, `deep_equal`, `validate`, `inspect`, `is_callable`, `isarray/islist`, `empty_dict`, `iter`, `F`。
- nvim では**ネイティブ実装をそのまま再エクスポート**(自前実装で上書きしない)。
- Neovim のソースをコピーする場合は Apache-2.0 のライセンス表記が必要。方針: 仕様準拠の**クリーンルーム実装**を基本とし、テストで同値性を担保する(コピーする場合は NOTICE を追加)。

### L2 core — 横断基盤
1. **convert**(値の双方向変換): Lua ⇔ Vim script。
   - `nil` / `vim.NIL` / `v:null`、`true/false` / `v:true/v:false` / 0,1
   - 空テーブルの曖昧さ → `vim.empty_dict()` と `vim.islist` 規約で解決
   - 整数/浮動小数(Lua 5.1 は区別なし → `math.type` 利用可能なら使用、なければ値で判定)
   - Funcref ⇔ Lua function(registry 経由)
   - blob、循環参照の検出
2. **registry**(コールバック表): 一意で衝突しない整数 ID、**重複キーなし**。`(kind, scope, key)` ではなく単調増加 ID に統一し、解除 API(`del_autocmd`, `del_keymap`, `delete_command`)で確実に解放。弱参照は使わず明示解放 + バッファ破棄時の自動掃除(`BufWipeout`)。
3. **errors**: 例外を Neovim 形式(`E5108: Error executing lua ...`)に近い形へ整形。未実装 API は `artemis: <name> is not supported on vim (tier C)` を投げる。
4. **has**(機能照会): `artemis.has('api.nvim_buf_set_extmark')` で実装階層を返す。プラグイン側のフォールバック分岐に使える。

### L3 vim.api — サポート階層
各 API を階層で管理し、`doc/` に自動生成の対応表を載せる。

| 階層 | 意味 | 例 |
|---|---|---|
| **A: 厳密** | 意味が同一にエミュレートできる | `nvim_buf_get_lines/set_lines`, `nvim_get_current_*`, `nvim_call_function`, `nvim_eval`, `nvim_command`, `nvim_exec2`, `nvim_replace_termcodes`, `nvim_feedkeys`, `nvim_get/set_option_value`, `nvim_create_user_command`, `nvim_create_augroup/autocmd`, `nvim_set_keymap`, `nvim_echo` |
| **B: 近似** | 動作するが差異あり(差異を文書化) | extmark(Vim: `prop_add` で代替、gravity/優先度に制限)、namespace、`nvim_set_hl`(`hlset()`)、`nvim_open_win`(float → `popup_create`)、`nvim_buf_attach`(`listener_add`)、`nvim_buf_set_text` |
| **C: 非対応** | 明示エラー | `nvim_open_term`, `nvim_ui_*`, `nvim_set_decoration_provider`, `vim.lsp`, `vim.treesitter` |

実装方針:
- **文字列組み立てを避ける**。`:map` / `:command` / `:autocmd` は可能な限り Vim の関数 API(`mapset()`, `autocmd_add()`, `getcmdline`/`prop_*`/`popup_*`)を使い、クォート問題を排除。
- **インデックス規約を一箇所に**: 0-based/1-based、byte/char/UTF-16 列、end-exclusive 等の変換を `core/pos.lua` に集約。
- Vim 側の `buffer`/`window` userdata と Neovim 側の整数ハンドルの差は、**ハンドルを常に整数**で扱う(`bufnr`/`win_getid()`)ことで統一。

### L4 非同期・イベントループ
- `vim.schedule` / `vim.defer_fn` → `timer_start`
- `vim.uv`(`vim.loop`)の**実用サブセット**: `new_timer`, `now`, `hrtime`, `fs_stat`, `fs_*` の一部(同期)、`spawn`(→ `job_start`)。完全な libuv は目指さない。
- `vim.system` → `job_start` + 出力収集(`:wait` は `job_status` ポーリング)
- `vim.wait`, `vim.notify`, `vim.ui.select/input`(標準実装)
- `vim.json` → `json_encode/decode`(`v:null` / 空 dict 規約を揃える)、`vim.regex` → `matchstrpos` 系

### L5 inject / facade — 本命
`require('artemis').setup{ inject = true }`(または `require('artemis.inject')`)で、Vim の既存グローバル `vim` テーブルに **欠けているフィールドだけを追加**する(既存の `vim.eval` 等は上書きしない)。
- `vim.api`, `vim.fn`, `vim.o/opt/g/b/w/t/v/env/bo/wo/go`, `vim.keymap`, `vim.cmd`, `vim.schedule` …
- `package.loaded` / `package.preload` に `vim.shared`, `vim.inspect`, `vim.iter`, `vim.uv`, `vim.keymap` などのサブモジュールを登録し、`require('vim.xxx')` を解決。
- 逆方向(Neovim 上の Vim 向けプラグイン): `vim.fn.popup_create` / `prop_add` / `job_start` / `ch_*` / `autocmd_add` 等を、`vim.fn` プロキシ層で nvim API(float window / extmark / `jobstart`)に**フォールバック解決**する。
- 従来の `require('artemis')` API(`create_command`, `fn.lexima.add_rule`, `g.x.y = …` 等)は**後方互換ラッパー**として残す。

## 4. ディレクトリ構成

```
lua/artemis.lua              # 後方互換エントリ(薄い再エクスポート)
lua/artemis/init.lua         # v2 エントリ: setup / has / 互換API
lua/artemis/host/{nvim,vim}.lua
lua/artemis/core/{convert,registry,errors,pos,has}.lua
lua/artemis/shared/*.lua     # split, tbl, iter, inspect, validate …
lua/artemis/api/{buf,win,tab,option,cmd,autocmd,keymap,extmark,hl,float,ui}.lua
lua/artemis/loop/{timer,job,system,fs}.lua
lua/artemis/inject.lua
test/spec/**                 # 両ホストで同一仕様を実行
test/plugins/**              # 実プラグインのスモークテスト
docs/{design.md,compat-table.md}
```

## 5. テスト戦略(互換性を機械的に担保)

1. **共通 spec を両ホストで実行**: 同じ Lua spec(busted 風の最小ランナーを自作、外部依存なし)を `nvim -l` / `vim -es --cmd 'lua ...'` の両方で走らせ、結果を比較。**Neovim ネイティブの挙動が正解**(オラクル)。
2. **差分テスト**: 同一入力に対し、Neovim ネイティブ `vim.api` と Vim 上のエミュレーションの出力を比較(行取得・オプション・autocmd 発火順など)。
3. **実プラグインのスモーク**: 純 API 系から段階的に。候補: mini.nvim(`mini.comment`, `mini.surround`, `mini.ai`)、Comment.nvim、nvim-surround。到達度を `docs/compat-table.md` に記録。
4. **CI マトリクス**: Vim 8.2 / 9.x(`+lua`)、Neovim stable / nightly、Lua 5.1 / 5.4 / LuaJIT。

## 6. 実装フェーズ

| Phase | 内容 | 完了条件 |
|---|---|---|
| **P0 調査** | Vim の `if_lua` 実機検証(`vim.fn` の有無、`vim.funcref`、`vim.type`、エラー伝播、`luaeval` の型変換、Lua バージョン)。※現環境の vim は `-lua` のため **+lua ビルドが必要**。 | 検証結果を `docs/host-notes.md` に記録 |
| **P1 基盤** | L0/L1/L2、テストランナー、CI | shared と convert が両ホストで spec 合格 |
| **P2 API コア** | 階層 A の `vim.api`、keymap/command/autocmd/option を registry ベースで再実装 | 既存 v1 API が新実装上で動く |
| **P3 inject** | `vim` テーブル注入、サブモジュール登録 | 小規模な Neovim プラグインが Vim で無改造起動 |
| **P4 非同期** | timer/job/system/uv サブセット | 非同期を使うプラグインが動く |
| **P5 表示系** | extmark/highlight/float/popup(階層 B) | mini.nvim の主要モジュールが動く |
| **P6 逆方向** | `vim.fn.popup_*` 等の Neovim 側フォールバック | Vim 向け Lua プラグイン例が Neovim で動く |

## 7. 主要リスクと対策

- **Vim の Lua 環境のバージョン差**(`vim.fn` 等の有無はパッチレベル依存の可能性): P0 で実測し、最低サポートバージョンを確定。
- **extmark / float の意味差**: 階層 B として差異を明記、`artemis.has()` で判定可能に。
- **callback の GC / リーク**: registry の明示解放 + 自動掃除。
- **性能**: 文字列 eval の往復が多い。`call` を多用し、`convert` はテーブル走査を最小化。バッファ全行取得などはバルク API を使う。
- **スコープ膨張**: 階層 C を明文化し、LSP/Treesitter は対象外と宣言。

## 8. 決めたいこと(要確認)

1. 最低サポート: Vim 9.0+ / Neovim 0.9+ でよいか。
2. 標準ライブラリはクリーンルーム実装(推奨)か、Neovim ソースのコピー(Apache-2.0 表記)か。
3. 優先ターゲットプラグイン(上記候補以外に動かしたいもの)。
4. 逆方向(Vim 専用機能の Neovim 上エミュレーション)の優先度。P6 まで後回しでよいか。
