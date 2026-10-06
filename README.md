# FX战士久留美 同人 · 2000万之路

《FX戦士くるみちゃん》（原作 でむにゃん / 作画 炭酸だいすき，KADOKAWA）的**非官方同人**像素 FX 肉鸽游戏。Godot 4.7。

主角福賀くるみ（久留美）从 30 万円起步，目标是取回母亲亏掉的 2000 万円。
行情由多因子算法实时生成；新闻、经济指标、央行、自然灾害、谣言、散户情绪、朋友的博客都会影响价格。

## 运行

```bash
# 用 Godot 4.7 打开本目录，或命令行：
D:/godot/Godot_v4.7.2-stable_win64_console.exe --path projects/kurumi-fx-rogue
```
首次运行前如果命令行报类找不到，先导入一次：`--headless --path . --import`。

## 模式
- **剧情模式**：跟着漫画逐卷改编。第 1~6 章（原作第 1~10 話）是新手教程，教完买卖、杠杆/强平、止损止盈、经济指标、散户情绪后解锁肉鸽。之后的章节复刻漫画中的经典行情战役（如 2015-01-15 瑞郎冲击）。
- **肉鸽模式**：3 幕（目标净资产 80 万 → 400 万 → 2000 万），分叉地图上有相場/精英/事件/商店/休息/Boss 节点；手法（遗物）、道具、诅咒、仲间（萌智子/芽吹/やす子）、FX 业者（海外 888 倍零 cut / 国内 25 倍会产生不足金 …）组成构筑。通关后可进入无尽模式与挑战度。
- **局外养成「相場勘」**：每局结束按进度结算点数，提升起始资金、メンタル、情报能力、解锁品种与业者。
- **经典战役**：剧情中读到的战役可单独重玩。

## 操作
空格 暂停/继续 · 1~4 速度 · B 买 · S 卖 · C 全部平仓 · Tab 切换品种 · Esc 菜单 · F11 全屏
图表：滚轮缩放 · 右键拖动 · 左键拖动持仓的 SL/TP 线改单。

## 目录
| 路径 | 内容 |
|---|---|
| `src/core/` | 行情引擎 `market_sim.gd`、账户 `account.gd`、事件 `event_engine.gd`、交易会话 `trade_session.gd`、久留美心理 `kurumi.gd`、肉鸽状态 `run_state.gd`、修正值 `mods.gd`、存档/数据 |
| `src/ui/` | 交易界面、K 线图、对话框、主题、像素图标、立绘加载 |
| `src/story/` | 剧情播放器、教学导演、章节索引 |
| `src/run/` | 肉鸽：开局、地图、交易节点、结算、局外养成 |
| `data/market/` | 货币/资产与品种参数 |
| `data/events/` | 经济指标、新闻/灾害/谣言模板、SNS |
| `data/story/chapters/` | 剧情章节（一章一个 JSON，新增即生效） |
| `data/run/` | 业者、手法、道具/诅咒、仲间、节点/Boss、事件、养成树 |
| `assets/` | 像素素材（ComfyUI 生成）、像素字体（Fusion Pixel，OFL）、音效 |
| `docs/` | `GDD.md` 设计文档、`story-format.md` 章节格式、`research/manga-reference.md` 原作调研（带出处）、`art-pipeline.md` |
| `scripts/` | `gen_assets.py` 像素素材生成、`gen_sfx.py` 音效合成 |
| `tests/` | 引擎自检、编译检查、平衡模拟、界面冒烟测试 |

## 漫画更新时怎么同步剧情
1. 在 `docs/research/manga-reference.md` 补上新话的事实与出处。
2. 按 `docs/story-format.md` 新建 `data/story/chapters/chNN.json`（`order` 递增、`requires` 指向上一章）。
3. 跑 `tests/compile_check.tscn` 确认 JSON 合法。游戏会自动出现新章节。

## 测试
```bash
G=D:/godot/Godot_v4.7.2-stable_win64_console.exe
$G --headless --path . res://tests/test_market.tscn      # 行情/账户/强平/钉住撤销自检
$G --headless --path . res://tests/compile_check.tscn    # 全部脚本与数据
$G --headless --path . res://tests/sim_balance.tscn -- --runs=16 --meta=3 --risk=0.1 --oracle   # 平衡模拟
$G --path . res://tests/smoke_ui.tscn                    # 界面冒烟（需要窗口）
```
截图调试：`$G --path . res://src/run/run_map.tscn -- --newrun --shot=<绝对路径.png> --shot-delay=2`

## 原作与素材说明
- 剧情事实只采用调研文档中有出处的内容；台词为转述，不照搬原作对白，不使用原作图片。游戏原创的教学段落在章节 `original` 字段中注明。
- 复刻的真实行情只使用公开报道中的关键价位（来源写在章节 `source` 字段）；其余行情为算法生成。
- 久留美立绘用 Anima + 角色 LoRA 生成后像素化；其他角色参考官方人设生成。字体 Fusion Pixel Font（SIL OFL 1.1）。
