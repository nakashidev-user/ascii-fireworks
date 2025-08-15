# ascii-fireworks

🎆 ファイル保存時に ASCII 文字で花火アニメーションを表示する Neovim プラグイン
夏っぽい雰囲気を Neovim に追加し、ファイル保存のたびに楽しい花火を楽しめます。

## 特徴

- ファイル保存時に自動で花火アニメーションを表示
- ファイルサイズと診断エラー数に基づいて派手さを自動調整
- 軽量で依存関係なし（純粋な Lua + Neovim API）
- 完全にカスタマイズ可能

## インストール

### lazy.nvim
```lua
{
  'nakashidev-user/ascii-fireworks',
  config = function()
    require('ascii-fireworks').setup()
  end
}
```

### packer.nvim
```lua
use {
  'nakashidev-user/ascii-fireworks',
  config = function()
    require('ascii-fireworks').setup()
  end
}
```

### vim-plug
```vim
Plug 'nakashidev-user/ascii-fireworks'

" init.lua または vimrc に追加
lua require('ascii-fireworks').setup()
```

## 使用方法

### 基本セットアップ
```lua
require('ascii-fireworks').setup()
```

### カスタム設定例
```lua
require('ascii-fireworks').setup({
  enable = true,
  events = { "BufWritePost" },           -- 反応するイベント
  duration_ms = 700,                     -- アニメーション総時間
  frame_interval_ms = 80,                -- フレーム間隔
  min_bytes_for_big = 4096,              -- この以上のサイズで派手に
  max_bursts = 5,                        -- 同時花火数の上限
  chars = { "*", "+", "x", "o", "·" },   -- 花火に使用する文字
  hl_groups = { "IncSearch", "WarningMsg", "String", "Type" }, -- ハイライトグループ
})
```

### 手動実行
```vim
:Fireworks
```

### ランタイム制御
```lua
-- 有効化/無効化
require('ascii-fireworks').enable()
require('ascii-fireworks').disable()
require('ascii-fireworks').toggle()
```

## 動作ロジック

花火の派手さは以下の要因で自動調整されます：

- **ファイルサイズ**: 4KB 以上のファイルで派手になります
- **診断エラー**: エラーが 0 個の場合に派手になります
- **強度レベル**: 1（控えめ）～ 3（派手）の 3 段階

## 設定項目

| 項目 | デフォルト値 | 説明 |
|------|-------------|------|
| `enable` | `true` | プラグインの有効/無効 |
| `events` | `{ "BufWritePost" }` | 花火を発火するイベント |
| `duration_ms` | `700` | アニメーション総時間（ミリ秒） |
| `frame_interval_ms` | `80` | フレーム更新間隔（ミリ秒） |
| `min_bytes_for_big` | `4096` | 派手な花火になるファイルサイズ閾値 |
| `max_bursts` | `5` | 同時に表示する花火の最大数 |
| `chars` | `{ "*", "+", "x", "o", "·" }` | 花火に使用する ASCII 文字 |
| `hl_groups` | `{ "IncSearch", "WarningMsg", "String", "Type" }` | ハイライトグループ |
| `random_seed` | `true` | 起動ごとの乱数シード初期化 |

## 要件

- Neovim 0.7.0 以上
- `vim.loop` と `vim.api.nvim_buf_set_extmark` のサポート

## ライセンス

MIT License
