# FX战士久留美 同人 · 2000万之路

《FX戦士くるみちゃん》（原作 でむにゃん / 作画 炭酸だいすき，KADOKAWA）的**非官方同人**像素 FX 肉鸽游戏。Godot 4.7。

主角福賀くるみ（久留美）从 30 万円起步，目标是取回母亲亏掉的 2000 万円。
行情由多因子算法实时生成；新闻、经济指标、央行、自然灾害、谣言、散户情绪、朋友的博客都会影响价格。

## 运行

```bash
G=D:/godot/Godot_v4.7.2-stable_win64_console.exe
cd projects/kurumi-fx-rogue
$G --headless --path . --import   # 首次运行 / 新增脚本或素材后先导入
$G --path .                        # 运行（或用 Godot 编辑器打开本目录）
```
存档在 `%APPDATA%\Godot\app_userdata\FX战士久留美 同人 · 2000万之路\save.json`。
测试时可在标题画面按 **Shift+F9** 解锁全部（教程完成 + 全章已读）。

## 模式
- **剧情模式**：跟着漫画逐卷改编，第 1~15 章覆盖原作第 1~53 話。第 1~6 章（原作第 1~10 話）是新手教程，完成后解锁肉鸽。第 11 章复刻 2015-01-15 瑞郎冲击。
- **肉鸽模式**：3 幕（净资产目标 80 万 → 400 万 → 2000 万），分叉地图上有相場/精英/事件/商店/休息/Boss；手法、道具、诅咒、仲间（萌智子/芽吹/やす子）、FX 业者组成构筑。通关后有无尽模式与挑战度 1~10。
- **局外养成「相場勘」**、**经典战役**（重玩剧情战役）、**图鉴**。

## 操作
空格 暂停/继续 · 1~4 速度 · B 买 · S 卖 · C 全部平仓 · Tab 切换品种 · Esc 菜单 · F11 全屏
图表：滚轮缩放 · 右键拖动 · 左键拖动持仓的 SL/TP 线改单。

## 文档
| 文档 | 内容 |
|---|---|
| [docs/maintenance.md](docs/maintenance.md) | **维护手册**：架构、关键约定与坑、常见维护任务、测试、已知问题 |
| [docs/data-reference.md](docs/data-reference.md) | 所有 JSON 数据、Mods 修正值、存档的字段参考 |
| [docs/story-format.md](docs/story-format.md) | 剧情章节格式、时间线动作、教学步骤条件、章节检查流程 |
| [docs/art-pipeline.md](docs/art-pipeline.md) | 美术素材管线（ComfyUI / LoRA / IC / Blender / 像素化） |
| [docs/GDD.md](docs/GDD.md) | 设计文档（与实现同步，含未实现清单） |
| [docs/research/manga-reference.md](docs/research/manga-reference.md) | 原作调研（剧情事实唯一来源，带出处） |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | 版本历史 |

## 目录
| 路径 | 内容 |
|---|---|
| `src/core/` | 行情 `market_sim.gd`、事件 `event_engine.gd`、账户 `account.gd`、交易会话 `trade_session.gd`、心理 `kurumi.gd`、修正值 `mods.gd`、肉鸽 `run_state.gd`、日期、存档、数据、场景切换 |
| `src/ui/` | 交易界面、K 线图、对话框、立绘、像素图标、序列帧、主题、音效 |
| `src/story/` | 剧情播放器、教学导演、章节索引 |
| `src/run/` | 肉鸽：开局、地图、交易节点、结算、局外养成 |
| `src/scenes/` | 启动、标题、章节选择、设置、经典战役、图鉴、调试沙盒 |
| `data/` | 行情/事件/剧情/肉鸽的 JSON 数据 |
| `assets/` | 像素素材、字体（Fusion Pixel，OFL）、音效 |
| `config/` | 素材生成清单 `asset-manifest.json` |
| `scripts/` | 素材生成、取图、序列帧像素化、Blender 金币、音效合成 |
| `tests/` | 引擎自检、编译检查、存档往返、平衡模拟、战役核对、界面冒烟、教程自动通关、自动播放检查 |

## 漫画更新时同步剧情
1. 在 `docs/research/manga-reference.md` 补上新话的事实与出处。
2. 按 `docs/story-format.md` 新建 `data/story/chapters/chNN.json`。
3. 按 story-format.md §5 跑检查（编译检查 → 教程驱动 → 自动播放检查 → 战役核对）。

## 测试
```bash
$G --headless --path . res://tests/test_market.tscn      # 行情/账户/强平/钉住撤销自检 → "== 失败 0 =="
$G --headless --path . res://tests/compile_check.tscn    # 全部脚本与数据 → "0 failures"
$G --headless --path . res://tests/test_save.tscn        # 肉鸽存档往返 → "SAVE ROUNDTRIP OK"
$G --path . res://tests/smoke_ui.tscn                    # 界面冒烟（需要窗口）→ "SMOKE DONE"
$G --path . res://tests/tutorial_driver.tscn             # 教程自动通关 → 每章 "步骤 n/n"
$G --path . res://tests/autoplay_check.tscn              # 自动播放段不卡死 → "0 stalled"
$G --headless --path . res://tests/sim_balance.tscn -- --runs=16 --meta=3 --risk=0.1 --oracle   # 平衡模拟
$G --headless --path . res://tests/check_battle.tscn -- --chapter=ch11                         # 战役关键数字
```
截图调试：`$G --path . res://src/run/run_map.tscn -- --newrun --shot=<绝对路径.png> --shot-delay=2`（更多参数见维护手册 §1）。

## 原作与素材说明
- 剧情事实只采用调研文档中有出处的内容；台词为转述，不照搬原作对白，不使用原作图片。游戏原创部分在章节 `original` 字段中注明。
- 复刻的真实行情只使用公开报道中的关键价位（来源写在章节 `source` 字段）；其余行情为算法生成。
- 久留美立绘：Anima + 角色 LoRA；萌智子/芽吹/やす子：以动画官网立绘为参考的 IC 方法；父母无官方立绘，用剪影。
- 字体 Fusion Pixel Font（SIL OFL 1.1）。
