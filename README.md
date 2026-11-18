# bloxstrike-mobile

ZOMBIES BloxStrike · Seeto.SolutionZ v2.5 手机版（免 key）

## 一键加载
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/bloxstrike-mobile.lua"))()
```

或者加载 loader：

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/robert80322-sys/bloxstrike-mobile/main/loader.lua"))()
```

## 手机浮层
- **BS**：开关菜单（右侧常驻，可拖动）
- **BHOP**：按住连跳
- **AIM**：按住瞄准（等价按住 MB1）

## 文件
| 文件 | 说明 |
|---|---|
| `bloxstrike-mobile.lua` | 手机版，14 个模块内联，242KB |
| `bloxstrike-seeto-keyless.lua` | PC 版（无浮层），同样免 key |
| `loader.lua` | 一行加载器 |

原版链路：WAD 混淆 → key UI → key-courier 校验 → GitHub init.lua → src/*.lua。
key 只是外层门面，本体是公开仓库代码，这里已全部内联。
