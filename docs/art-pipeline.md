# 美术素材管线

所有像素素材由 ComfyUI 生成高清原图，再在本地用 Pillow 像素化。清单在 `config/asset-manifest.json`，生成记录在 `assets/sprites/index.json`。

## 流程
```
高清原图（ComfyUI）→ output/hires/<id>.png（不入库）
  → 去白底（立绘/图标/Q版）→ 胸像裁切（立绘）→ BOX 缩小 → 限色 → 透明二值化 → 1px 深色外描边
  → assets/sprites/<类别>/<id>.png（入库）
```
| 类别 | 目录 | 像素尺寸 | 颜色数 | 用途 |
|---|---|---|---|---|
| 立绘 portrait | `portraits/` + `portraits_small/` | 128×128 / 64×64 | 32 / 24 | 对话框（×2 显示）/ 交易画面头像 |
| 背景 bg | `bg/` | 320×180 | 48 | 剧情、地图（×2 显示） |
| CG | `cg/` | 320×180 | 48 | 标题、结算 |
| 图标 icon | `icons/` | 32×32 | 16 | 手法、道具 |
| Q版 chibi | `chibi/` | 48×48 | 24 | 肉鸽地图上的久留美 |

## 角色来源
| 角色 | 方法 | 依据 |
|---|---|---|
| 福賀くるみ（久留美） | Anima t2i + 角色 LoRA `kurumi.safetensors`（触发词见清单） | LoRA |
| 小金萌智子 / 山師芽吹 / 高根やす子 | **Anima IC 方法**：以动画官网立绘为参考图，只改表情/动作 | 官方立绘（`temp/kurumi-ref/official/`，不入库、不进游戏） |
| 父亲·郁夫 / 母亲·梢 | 剪影风（看不清脸） | 官网未找到官方立绘，**不臆造长相** |
| 久留美（初三，2008） | LoRA + 通用学生服 | 校服样式为游戏原创 |

## 命令
```bash
cd projects/kurumi-fx-rogue
python scripts/gen_assets.py --status            # 缺失清单
python scripts/gen_assets.py                     # 生成全部缺失（t2i 类）
python scripts/gen_assets.py kurumi_cry --reroll # 换种子重画
python scripts/gen_assets.py --pix-only <id>     # 只用已有原图重新像素化
python scripts/gen_assets.py --contact           # 重做总览拼图 output/contact_sheet.png
```

### IC 参考图（仲间立绘）
`anima-ic` 模板需要绕过 ControlNet 组，脚本自带的提交方式在当前 ComfyUI 上不出图；请用 comfyui-contract MCP 提交：
1. `comfyui_generate(template="anima-ic", image="D:/agent/temp/kurumi-ref/official/flat_<角色>.png", prompt=<清单 nl>, seed=<清单 seed>)`
2. `python scripts/fetch_comfy_job.py <job_id> <asset_id>`（取回节点 24 的裁切结果到 `output/hires/`）
3. `python scripts/gen_assets.py --pix-only <asset_id>`

参考图 `flat_*.png` 是官网透明底立绘铺白底后的版本。

## 其他
- 白色物体（枕头、白猫）用绿底生成，清单里的 `kind_override: {"bg_key": "auto"}` 让抠图改为取四角颜色。
- 金币动画由 Blender 渲染：`scripts/blender_coin.py` → `scripts/pixelize_frames.py` → `assets/sprites/anim/coin.png`（8 帧 24×24）。
- 小号 UI 图标（新闻类型、地图节点、心形等）是 `src/ui/pixel_icons.gd` 里手写的 ASCII 像素画。
- 音效由 `scripts/gen_sfx.py` 合成（8-bit 方波/三角波/噪声）。
- 缺图时游戏会用占位：立绘 → 程序绘制的剪影（发色取自 `data/story/characters.json`），图标 → 像素星形。
