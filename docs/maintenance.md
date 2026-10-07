# 维护手册

给之后维护、扩展本项目的人（包括 AI agent）看的总说明。先读这一篇，再按需查：

| 文档 | 内容 |
|---|---|
| `README.md` | 项目简介、运行方法、目录 |
| `docs/maintenance.md` | **本文**：架构、关键约定与坑、常见维护任务、测试、已知问题 |
| `docs/data-reference.md` | 所有 JSON 数据与存档的字段参考 |
| `docs/story-format.md` | 剧情章节格式、时间线动作、教学步骤条件、章节检查流程 |
| `docs/art-pipeline.md` | 美术素材生成管线（ComfyUI / LoRA / IC / Blender / 像素化） |
| `docs/GDD.md` | 设计文档（含与实现的差异说明） |
| `docs/research/manga-reference.md` | 原作调研（唯一的剧情事实来源，带出处） |
| `docs/CHANGELOG.md` | 版本历史 |

---

## 1. 快速开始

```bash
G=D:/godot/Godot_v4.7.2-stable_win64_console.exe
cd projects/kurumi-fx-rogue
$G --headless --path . --import      # 首次 / 新增 class_name 脚本或素材后必须跑（刷新类缓存与导入）
$G --path .                           # 运行游戏
$G --headless --path . --export-debug "Android" output/kurumi-fx-rogue.apk   # 打包手机 APK（依赖见 §7）
```
- 引擎：Godot **4.7.2**，GDScript，渲染器 `gl_compatibility`。视口 640×360，`viewport` 拉伸 + 整数缩放，默认最近邻采样。
- 字体：Fusion Pixel 12px（`assets/fonts/`，OFL），文字尺寸只用 12 / 24。
- 存档：`C:/Users/<用户>/AppData/Roaming/Godot/app_userdata/FX战士久留美 同人 · 2000万之路/save.json`
  （删除它 = 全新存档；设置画面也有「清除全部存档」）。
- 测试用快捷：标题画面 **Shift+F9** 把教程标记为完成并读完全部章节（只改当前存档）。

### 调试启动参数（写在 `--` 之后，`src/core/game.gd` 解析）
| 参数 | 作用 |
|---|---|
| `--shot=<绝对路径.png> --shot-delay=<秒>` | 延时截图后退出（看界面效果用） |
| `--scene=res://...` | 启动后跳到某场景 |
| `--chapter=ch04 --scene-index=2` | 配合 `res://src/story/story_player.tscn` 直接打开某章某场景 |
| `--newrun` | 用固定种子 777 新开一局肉鸽（不写盘），配合 `res://src/run/run_map.tscn` |
| `--node=<节点id>` | 配合 run_trade 场景 |
| `--touch` | 按触屏设备显示操作提示（`Game.touch`；真正的触摸事件仍需手机或 `tests/touch_check`） |

例：`$G --path . res://src/run/run_map.tscn -- --newrun --shot=D:/tmp/map.png --shot-delay=2`

`res://src/scenes/sandbox.tscn` 是调试沙盒：直接进入一段全情报能力打开的交易。

---

## 2. 架构

### 2.1 目录
```
src/core/    纯逻辑（可无界面测试）
  market_sim.gd     行情引擎 MarketSim
  event_engine.gd   经济日历/新闻/谣言/SNS EventEngine
  account.gd        账户、持仓、强平、不足金、掉期 Account
  kurumi.gd         久留美心理（メンタル、暴走、表情、台词）Kurumi
  mods.gd           修正值叠加 Mods
  trade_session.gd  一段交易 = 行情+事件+账户+心理+时间线 TradeSession
  run_state.gd      肉鸽一局 RunState
  game_date.gd      交易日/日期/金额格式 GameDate
  db.gd save.gd game.gd   自动加载：数据缓存 / 存档 / 场景切换与调试参数
src/ui/      交易界面 TradeScreen、K线 ChartView、对话框 DialogueBox、立绘 Portraits、
             手绘像素图标 PixelIcons、序列帧 AnimSprite、主题 UI(ui_theme.gd)、音效 Sfx、背景音乐 Bgm
src/story/   StoryPlayer(story_player.gd)、TutorialDirector、StoryDB
src/run/     run_hub(开局) run_map(地图/事件/商店/休息) run_trade(交易节点) run_result(结算) meta_screen(养成) map_lines
src/scenes/  boot title chapter_select settings battles codex sandbox
data/        内容数据（JSON）       config/  素材清单（.gdignore）
assets/      字体、像素素材、音效    scripts/ Python/Blender 工具（.gdignore）
tests/       测试场景               docs/    文档（.gdignore）   output/ 生成物（.gdignore，不入库）
```
自动加载顺序（project.godot）：`DB → Save → UI → Sfx → Bgm → Game`。UI 依赖 Save（读配色设置），Bgm 依赖 Save（读音量），Game 依赖 RunState。

### 2.2 场景流转
```
boot → title ─┬─ chapter_select → story_player ──(章末)→ 下一章 / chapter_select
              ├─ run_hub ─→ run_map ⇄ run_trade（交易/精英/Boss 节点）
              │               └→ run_result（失败/通关/放弃）→ meta_screen / run_hub
              ├─ meta_screen   ├─ battles → story_player(battle_only)   ├─ codex   └─ settings
```
跨场景参数用 `Game.goto(scene, params)` 传，目标场景读 `Game.params`。进行中的肉鸽局在 `Game.run`，并随时 `run.save()` 写入 `Save.data.run`。

### 2.3 一段交易里的对象
```
TradeScreen(界面) ──持有── TradeSession
                              ├ MarketSim   行情（units/factors/instruments/effects）
                              ├ EventEngine 日历、随机事件、SNS（往 MarketSim 加 effect）
                              ├ Account     持仓/保证金/强平（读 MarketSim 价格）
                              ├ Kurumi      メンタル/表情/台词
                              └ Mods        修正值（肉鸽时与 RunState 共用同一个 Mods）
剧情：StoryPlayer 创建 TradeSession+TradeScreen，再挂一个 TutorialDirector 驱动步骤
肉鸽：run_trade 用 RunState.trade_config(node) 生成配置，结束后 RunState.settle_trade() 结算
```

### 2.4 每个 tick 的顺序（`TradeSession.advance()`）
1. `_run_script()` 执行到期的时间线动作
2. `events.update()`：指标发布（发布前 1 tick 扩点差）、剧情定时事件、随机新闻、待发布标题、SNS
3. `market.step()`：
   效果收集（level 冲击在**开盘瞬间**生效 → 形成跳空）→ 自发跳跃 → 布朗桥引导 → 钉住约束 → 记录开盘价
   → 因子扩散 → 单元扩散（regime 切换、GARCH）→ 钉住约束 → 干预判定 → 写 OHLC/点差/散户情绪/止损猎杀 → tick+1
4. `account.process_tick()`：止损/止盈（用本根 K 线的 OHLC 判断，跳空按开盘价成交）、追踪止损、强平
5. `kurumi.on_tick()`；跨日时结算掉期（周三→周四 ×3）、メンタル回复、周末跳空
6. `ticked` 信号 → 界面每帧最多刷新一次；检查结束条件（broken / bust / goal / time）

时间单位：1 tick = 15 分钟，1 交易日 = 96 tick，从东京 07:00（纽约收盘）开始。

---

## 3. 关键约定与坑（改代码前必读）

1. **GDScript 类型推断**：`var x := dict.key` / `:= {...}.get()` 这类从 Variant 推断会被当作错误（编译失败）。
   从 Dictionary/JSON 取值时写显式类型：`var x: float = d.value`。新增脚本后跑 `tests/compile_check.tscn`。
2. **JSON 数字都是 float**：`[1.0, 2.0].has(1)` 为 false。数组比较整数前转 float（`EventEngine._random_news` 有例子）。
3. **新增 `class_name` 后要 `--import`**，否则命令行运行时报「Identifier not declared」。
4. **自动播放段与自动暂停**（`TradeScreen`）：
   系统性的暂停（新闻、指标、告警、强平）一律用 `_auto_pause()`——速度被剧本锁定时它什么都不做；
   弹出模态框时先记下 `prev := speed`，关闭时调用 `_modal_resume(prev)`。直接 `_set_speed(0, true)` 会导致玩家无法恢复（第 1 章卡死 bug 的根因）。
5. **教学步骤结束**：`finish` 步骤要把 `TutorialDirector.i` 置为 `steps.size()`，否则 `win: {"steps": true}` 判为失败（已修，改 director 时注意）。
6. **起始价在预热之后校准**（`TradeSession._init`），并把预热历史整体等比缩放；预置持仓的 `entry` 按校准后的价位设计。
7. **报价停止 `halted`**：期间不能下单、手动平仓、止损止盈、强平都延后到恢复报价时，以恢复后的价格成交（复刻瑞郎冲击「打穿」的关键）。
8. **Mods 规则**：键名以 `_mult` 结尾相乘，其余相加；临时效果用 `set_layer(名字, {...})` / `remove_layer()`，不要直接改默认值。肉鸽每个节点结束会 `rebuild_mods()`，节点内的临时层自然消失。
9. **确定性**：行情、事件、久留美台词都由种子决定。剧情章节固定 `seed`；肉鸽节点种子 = `seed_value*31 + hash(节点id)%100000`。
10. **肉鸽存档字段**：`RunState` 新增需要持久化的成员时，加入 `SAVE_KEYS`；`from_dict` 会把 JSON 的 float 转回 int 型成员。
    `Save._default()` 新增键后旧存档会被 `_merge` 自动补齐。
11. **金额与净资产**：Boss 目标比的是「净资产 = 资金 − 借金」，所以借钱不能直接过关，只能当本金。借金按年利 109.5% 每交易日复利。
12. **版本控制**：仓库根的 `.git/info/exclude` 全局忽略 `data/`、`assets/`；本项目 `.gitignore` 用 `!data/`、`!assets/` 放回。
    `output/`、高清原图不入库。仓库 `core.autocrlf=true`，提交时出现 LF/CRLF 警告属正常。
13. **用 Python 改源码/JSON** 时用 `python -X utf8`，按二进制读写或指定 `encoding='utf-8', newline='\n'`，否则中文与换行会被系统编码破坏。
14. **剧情事实**：任何章节内容都要能在 `docs/research/manga-reference.md` 找到出处；查不到就写成游戏原创并标注，或者不写。
15. **触屏输入**：每个功能都要有屏幕按钮或手势，键盘只能当加速器。Godot 默认 `emulate_mouse_from_touch`，
    所以 `Button` 与 `_gui_input` 里的鼠标事件在手机上直接可用（单指触摸 = 左键）；**右键永远不会被模拟**，
    所以图表平移不能只写右键（`ChartView` 里单指拖空白区域也平移）。双指手势在 `ChartView._gui_input` 处理
    `InputEventScreenTouch/Drag`，期间用 `_multitouch` 屏蔽触摸模拟出的鼠标事件，否则会边缩放边改 SL/TP 单。
    手机端显示在 `Game._setup_mobile_display()` 把 `content_scale_stretch` 切成小数缩放（桌面仍整数缩放，640×360 布局不变）。
    - **不要用“按下就算长按”**：对话框的快进要按住 ≥`DialogueBox.HOLD_DELAY`（0.45 秒）才生效，轻点只前进一句。
    - **Esc / 返回键**：`project.godot` 设了 `quit_on_go_back=false`，安卓返回键与“没人处理的 Esc”都进 `Game.back()`：
      当前场景有 `_on_back() -> bool` 就先交给它（剧情 `story_player` 开关菜单；交易 `TradeScreen.on_back()` 开关暂停菜单），
      否则菜单类界面（`Game.BACK_TO_TITLE`）回标题、标题画面连按两次退出。新加的“游戏中”场景要实现 `_on_back()`，
      新加的菜单界面要加进 `BACK_TO_TITLE`。
    - **tooltip 在手机上靠长按**：`Game` 在单指按住 0.5 秒不动时显示手指下控件的 `tooltip_text`，并让松手不触发按钮。
      所以说明文字放 `tooltip_text` 就行；但 **Label 默认 `MOUSE_FILTER_IGNORE`**，要显示说明得设成 `PASS`。
    - **操作提示分平台**：`Game.touch`（手机或 `-- --touch`）为真时显示触屏说明（对话框提示行、暂停菜单、设置页），否则显示快捷键。
    - **代码创建的全屏控件**在 `_ready`（已进树）里要用 `set_anchors_and_offsets_preset(PRESET_FULL_RECT)`；
      只用 `set_anchors_preset` 会保持 0×0——收不到点击、子弹窗的遮罩也不显示（DialogueBox / TradeScreen 曾经如此）。
      进树前（`add_child` 之前）调用 `set_anchors_preset` 没问题。
    - **`UI.rich()` 放进 HBox 时必须给 `custom_minimum_size.x`**：它开了自动换行，最小宽度是 0，HBox 不给宽度就逐字换行，
      弹窗被撑到上千像素高（肉鸽结算画面曾经如此，见 `tests/result_check`）。直接放进 `UI.modal` 的 VBox 没问题（VBox 给满宽）。
    改输入相关代码后至少跑 `touch_check`、`smoke_ui` 与 `tutorial_driver`。

---

## 4. 常见维护任务

### 4.1 漫画更新了 → 加新章节
1. 调研新话，补进 `docs/research/manga-reference.md`（事实 + 来源 URL + 置信度）。
2. 新建 `data/story/chapters/chNN.json`（`order` 递增，`requires` 指向上一章；连载中的章节加 `wip:true`）。格式见 `docs/story-format.md`。
3. 新角色暂无立绘：对话里用 `"who":"narrator","name":"名字"`。要做立绘见 4.6。
4. 按 story-format.md §5 跑检查。原来的最后一章如果带 `wip`，内容补完后去掉。

### 4.2 加一个手法（遗物）
在 `data/run/relics.json` 加一条：效果能用现有 Mods 键表达的话**只改数据**。
需要新机制时：在 `Mods.DEFAULTS` 加键 → 在 Account / Kurumi / EventEngine / ChartView / RunState 里读取它 → 写进 data-reference.md §5。
图标：在 `config/asset-manifest.json` 加一个 `icon` 类素材并生成（4.6），缺图时显示像素星形占位。

### 4.3 加道具 / 诅咒
`data/run/items.json`。道具 `effect` 现有键不够用时，改 `RunState.use_item()`（地图上用）和 `run_trade.gd` 的 `_use_item()`（交易中用）。
诅咒的 `mods` 不够时，特殊效果写在 `run_trade.gd`（如 posipos）或 `RunState.settle_trade()`（如 tax）。

### 4.4 加地图事件 / 精英 / Boss
- 事件：`data/run/events.json`，效果键见 data-reference.md §4；新键要改 `RunState.apply_effects()`。
- 精英：`nodes.json` 的 `elites[]`，用 `market/events` 改参数（`mult:true` 为相乘），或 `script` 加定时事件。
- Boss：`nodes.json` 的 `bosses[]`（`act` 决定出现在第几幕），同样用参数 + 时间线；需要新动作时在 `RunState._apply_mod_block()` 里转换。

### 4.5 加仲间
1. `data/run/friends.json` 加一条（被动用 `passive` 里的 Mods 键）。
2. 主动能力：在 `run_trade.gd` 的 `_use_friend()` 加分支；每日效果加在 `_on_day()`。
3. 解锁：在对应剧情章节 `unlock_on_clear` 加 `friend_<id>`，并加一个 `unlock` 场景说明。
4. 立绘：`assets/sprites/portraits/<id>_<face>.png`（及 `portraits_small/`），`data/story/characters.json` 加名牌颜色。
5. 有专属事件就在 events.json 写 `requires_friend`。

### 4.6 加/重画素材
见 `docs/art-pipeline.md`：在 `config/asset-manifest.json` 加条目 → `python scripts/gen_assets.py <id>` → `$G --headless --path . --import`。
官方人设参考的角色用 anima-ic（经 comfyui-contract MCP），父母等没有官方立绘的角色保持剪影，不臆造长相。
抠图走 AI 蒙版（art-pipeline.md「抠图」节）：只改了像素化参数时用 `--pix-only`，不需要重画原图；抠图有问题先看 `output/masks/<id>.png`。

### 4.6.1 加/换 BGM
1. 开源曲：`config/bgm-oss.json` 加 source 并在 `cues` 里映射 → `python scripts/import_oss_bgm.py`。自制曲：`config/bgm-cues.json` → `scripts/gen_bgm.py`（并从 bgm-oss 的 cues 删掉该 id）。见 `docs/bgm.md`。
2. 在用的地方调用：场景代码 `Bgm.play("<id>")`；剧情场景写 `"bgm": "<id>"`；临时盖在上面用 `Bgm.overlay()` / `Bgm.clear_overlay()`。缺 ogg 时静音不报错。
3. `$G --headless --path . --import` 后跑 bgm_check / compile_check / smoke_ui。

### 4.7 加品种 / 货币 / 经济指标 / 新闻
- 货币：`data/market/units.json`；品种：`instruments.json`（要解锁的写 `unlock` 并在 meta.json 加研究节点）。
- 指标：`data/events/indicators.json`；新闻：`data/events/news.json`（`kind` 决定久留美台词 `news_<kind>`，新 kind 记得在 barks.json 加台词）。
- 改完跑 `tests/test_market.tscn`，看各品种日波动是否仍在 0.2%~3% 区间。

### 4.8 调难度
1. 改 `data/run/nodes.json` 的幕参数（`target`、`market.trend_mult/regime_days/range_bias/vol_mult/hunt_prob`、`events.*`）或 meta.json 的养成数值。
2. 跑平衡模拟：
   ```bash
   $G --headless --path . res://tests/sim_balance.tscn -- --runs=16 --meta=0 --risk=0.05            # 零养成、均线机器人
   $G --headless --path . res://tests/sim_balance.tscn -- --runs=16 --meta=3 --risk=0.10 --oracle   # 满养成、知道隐藏趋势
   ```
   参数：`--meta=0~3`（养成程度）、`--risk`（单笔风险占净值）、`--oracle`（直接读隐藏 regime）、`--broker=domestic|overseas`。
3. 当前基线（2026-10）：零养成均线机器人几乎全灭于第一幕；满养成 oracle 风险 10% 第一幕通过约 70%、16 局中通关约 1 局。
   机器人不会用新闻提前量、指标预感、芽吹预言、商店，所以人类上限更高。调整后请记录新的基线。

---

## 5. 测试一览（`tests/`）
| 场景 | 需要窗口 | 作用 |
|---|---|---|
| `test_market.tscn` | 否 | 行情统计（120 日各品种日波动）、开平仓损益、国内业者强平产生不足金、零 cut、钉住撤销、20 天随机事件 |
| `compile_check.tscn` | 否 | 加载 `src/` 全部脚本 + 解析全部章节与肉鸽数据 |
| `test_save.tscn` | 否 | RunState → JSON → RunState 往返一致 |
| `sim_balance.tscn` | 否 | 平衡模拟（见 4.8） |
| `check_battle.tscn -- --chapter=chNN` | 否 | 无界面跑某章交易场景，打印最低价/收盘/不足金 |
| `smoke_ui.tscn` | 是 | 肉鸽交易节点（含仲间主动、自动下单）→ 地图弹窗；所有剧情交易场景快进 |
| `tutorial_driver.tscn [-- --chapter=chNN]` | 是 | 按每一步 until 模拟玩家操作，检查教学/剧情步骤能否走完（默认只跑教程章节） |
| `autoplay_check.tscn` | 是 | 真实时间、不按速度键，确认自动播放段（ch01/ch04/ch11/ch12）不会被自动暂停卡住 |
| `touch_check.tscn [-- --shots=<绝对目录>]` | 是 | 注入 `InputEventScreenTouch`：对话框轻点只前进一句、长按快进、「跳过」；长按看说明且不触发按钮；返回键开关剧情菜单/交易暂停菜单。`--shots` 顺便存三张截图 |
| `result_check.tscn [-- --shots=<绝对目录>]` | 是 | 肉鸽结算画面 5 种结局的弹窗与按钮都在 640×360 内（会写存档，结束时还原本机存档文件） |
| `bgm_check.tscn` | 否 | BGM：每个曲目 id 都能找到并加载成循环 OGG、章节引用的 id 都在 `tracks.json`、play/overlay/clear/stop 状态切换 |

全部跑一遍（约 5 分钟）：
```bash
for t in test_market compile_check test_save; do $G --headless --path . res://tests/$t.tscn; done
for t in smoke_ui tutorial_driver autoplay_check touch_check result_check; do $G --path . res://tests/$t.tscn; done
$G --headless --path . res://tests/bgm_check.tscn   # BGM 清单/文件/状态切换 → "BGM CHECK: 0 failures"
```
判定：test_market 末尾 `== 失败 0 ==`；compile_check `0 failures`；test_save `SAVE ROUNDTRIP OK`；
smoke `SMOKE DONE` 且无 `SCRIPT ERROR`；tutorial_driver 每个场景「步骤 n/n」；autoplay_check `0 stalled`；touch_check `0 failures`。
**注意**：`smoke_ui` 会把 `Save.data` 重置为默认值后跑完一个肉鸽交易节点（`run_trade._on_done` 里 `run.save()` 落盘），
即**覆盖本机的 `user://save.json`**；在意本机进度先备份存档。`touch_check` 不写盘。
退出时的 `ObjectDB instances leaked` / `resources still in use` 警告来自测试里未释放的会话，可忽略。

---

## 6. 已知问题与待办
| 项 | 说明 / 位置 |
|---|---|
| 通关特殊奖励未实现 | 设计中的「未知事件（暴涨/暴跌/特殊曲线）」只有文字占位：`src/run/run_map.gd` 的 `_victory()` |
| 独立的经典战役 | 「经典战役」目前只重玩剧情里 `battle` 标记的交易场景；独立复刻战役可做成 `data/battles/` + 改 `src/scenes/battles.gd` |
| 未使用的字段 | Mods `swap_reinvest`、Boss `intervene_prob`（干预概率写死在 `MarketSim._maybe_intervene`）、barks `hunt`、SNS `loss/win`、settings `fullscreen`、story `current` |
| 挂单（限价/逆限价单） | 未实现，只有市价单 + SL/TP + 追踪止损 |
| 海外业者「出金拒否」等风险事件 | GDD 提过，未实现 |
| 立绘覆盖 | 新章人物（酒田いなご、善波なな、月森きずな）无立绘；父母为剪影（官网无官方立绘） |
| 原作资料缺口 | 第 1~30 话无逐话资料；母亲交易澳元/日元仅单一博客来源；漫画柜中文章节标题未抓取（见调研文档 §6） |
| 平衡 | 只有机器人模拟，缺真人试玩数据 |
| 导出 | 已配置 Android 预设（`export_presets.cfg`）：`$G --headless --path . --export-debug "Android" output/kurumi-fx-rogue.apk`；Windows/桌面预设仍未加 |
| 触屏细节 | 图表缩放以右端为锚点（不是捏合中心）；按钮高 12~13 视口像素（1080p 手机约 6mm），偏小但未改布局；部分说明挂在 `MOUSE_FILTER_IGNORE` 的 Label 上（如地图侧栏），桌面悬停与手机长按都看不到 |
| 顶栏目标文字 | 太长时省略号截断（为保住右上「菜单」），如第 1 章「【回放 · 示意走势】 剩 8 天」看不到剩余天数 |
| 真机未验 | 返回键路由、长按说明、双指缩放只在桌面用注入事件测过（`touch_check`），未上真机 |
| 手机显示 | 用 `CONTENT_SCALE_ASPECT_KEEP`，非 16:9 屏幕上下留黑边；若要撑满可改用 `EXPAND`，但 640×360 的绝对坐标布局会露出空白区，需先改成自适应 |
| 手机与桌面差异 | 存档在关窗口、切后台（`NOTIFICATION_APPLICATION_PAUSED`）、标题画面返回键退出时落盘；交易中的行情状态不落盘（切后台被回收丢的是当前节点进度）；剧情中途退出下次从本章开头开始 |
| 每个 tick 的界面刷新 | 已节流为每帧一次；若在低端机卡顿，可降低 `ChartView` 重绘频率或缓存 K 线聚合 |

---

## 7. 外部依赖与环境
| 依赖 | 用途 | 位置 |
|---|---|---|
| Godot 4.7.2 | 引擎 | `D:/godot/Godot_v4.7.2-stable_win64_console.exe` |
| ComfyUI（aki 整合包） | 生成素材 | `D:/ComfyUI-aki-v3.2/ComfyUI`，`http://127.0.0.1:8188`，可用 comfyui-contract MCP 启停 |
| Anima + `kurumi.safetensors` LoRA | 久留美立绘 | ComfyUI 模型目录；LoRA 触发词见 asset-manifest |
| ComfyUI-RMBG + `BiRefNet_toonout` | 立绘/图标/Q版 AI 抠图 | `ComfyUI/custom_nodes/ComfyUI-RMBG`；模型 `ComfyUI/models/RMBG/BiRefNet/`（首次自动下载）。蒙版缓存 `output/masks/` |
| Blender 5.x | 金币序列帧 | `scripts/blender_coin.py`（或 Blender MCP） |
| Python 3 + Pillow | 像素化、音效 | `scripts/*.py` |
| 官方人设参考图 | IC 生成仲间立绘 | `D:/agent/temp/kurumi-ref/official/`（不入库、不进游戏） |
| Godot 4.7.2 导出模板 | 打包 Android | `%APPDATA%/Godot/export_templates/4.7.2.stable/`（`android_debug.apk` / `android_release.apk` / `android_source.zip`）。缺模板时 `--export-debug` 会报「缺少模板」 |
| Temurin JDK 17 | apksigner 签名 / gradle | `D:/tools/jdk17/jdk-17.0.13+11`（编辑器设置 `export/android/java_sdk_path`） |
| Android SDK | build-tools / platform-tools / platforms | `D:/tools/android-sdk`（`export/android/android_sdk_path`；已装 `build-tools;35.0.0`、`platforms;android-35`、`platform-tools`） |
| 调试签名 | debug APK | `%APPDATA%/Godot/keystores/debug.keystore`（口令均为 `android`，`export/android/debug_keystore`） |
