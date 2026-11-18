# bloxstrike-mobile

ZOMBIES BloxStrike · Seeto.SolutionZ v2.5 手机版（免 key）

## 一键加载
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/bloxstrike-mobile.lua?v=2"))()
```

## 功能
- **右侧悬浮按钮**：BS（开关菜单）/ AIM（按住瞄准）/ BHOP（按住连跳）
- **「手机」页**（菜单里）
  - 悬浮按钮：显示开关、按钮大小、一键重置位置
  - 按钮位置：BS / AIM / BHOP 各自的 X、Y 滑块（在菜单里调，不靠拖）
  - 皮肤修改器：开关 + 「关闭皮肤修改器」按钮
- 菜单支持触屏拖动 / 滑块 / 按钮（Linoria 打了 Touch 兼容）

## 文件
| 文件 | 说明 |
|---|---|
| `bloxstrike-mobile.lua` | 手机版：14 个主模块 + 8 个 Skinchanger 模块全部内联（473KB） |
| `bloxstrike-seeto-keyless.lua` | PC 版（无浮层），免 key |
| `loader.lua` | 一行加载器 |

原版链路：WAD 混淆 → key UI → key-courier 校验 → GitHub init.lua → src/*.lua。
key 只是外层门面，本体是公开仓库代码，这里已全部内联。
