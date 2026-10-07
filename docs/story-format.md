# 剧情章节格式（data/story/chapters/*.json）

剧情模式**跟着漫画走**：一个章节文件 = 原作一话或几话。漫画更新后新增一个 JSON 即可——
`src/story/story_db.gd` 会自动扫描目录并按 `order` 排序，章节选择画面、经典战役菜单都会自动出现新内容。

相关代码：`src/story/story_player.gd`（播放场景）、`src/story/tutorial_director.gd`（交易场景里的步骤）、
`src/core/trade_session.gd`（交易配置与时间线动作）、`src/ui/dialogue_box.gd`（对话框）。

## 0. 原则（必须遵守）
- **只写有出处的情节**。事实统一记在 `docs/research/manga-reference.md`，章节 `source` 字段写清楚引用了哪些小节/来源编号。
- 台词是**转述/改编**，不照搬原作对白，不使用原作图片。
- 为教学或游戏性加的内容是**游戏原创**，必须写进 `original` 字段。
- 行情是算法生成的；复刻真实事件时只用公开报道核实过的关键价位做关键帧（`guide`），并在 `source` 注明来源。
- 涉及自杀、债务等沉重内容要克制，不渲染细节；相关章节末尾附求助提示（参考 ch12/ch13）。

## 1. 顶层字段
| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✓ | 唯一 id，如 `ch16` |
| `order` | ✓ | 排序数字（可用小数插队，如 15.5） |
| `title` | ✓ | 显示标题 |
| `manga` | | 对应原作话数，如 `第54〜56話` |
| `period` | | 作中时间 |
| `source` | ✓ | 出处说明 |
| `original` | | 游戏原创/推断部分说明 |
| `tutorial` | | 新手教程章节（章节选择显示「教程」，教程自动通关测试会跑它） |
| `tutorial_complete` | | 读完后标记教程完成 → 解锁肉鸽（目前是 ch06） |
| `battle` | | 含经典战役复刻（出现在「经典战役」菜单；也可在单个 trade 场景上写 `battle`） |
| `wip` | | 原作连载中、本章内容未完 |
| `requires` | | 需要先读完的章节 id 列表（通常是上一章） |
| `unlock_on_clear` | | 读完后获得的解锁标签（如 `friend_yasuko`），标签一览见 data-reference.md §7 |
| `scenes` | ✓ | 场景数组 |

## 2. 场景类型

所有场景都可以带 **`bgm`**（`assets/bgm/<id>.ogg` 的 id，曲目表见 `docs/bgm.md` §3；`""` = 静音）。
播放第 i 个场景时向前找最近一个带 `bgm` 的场景播放，所以只需在换曲的场景上写；同一首不会重头播放。
一章都没写 `bgm` 时沿用进入剧情前的曲子（章节选择 = menu）。

### title_card
`{"type":"title_card","text":"2008年 秋","sub":"副标题","bg":"bg_living_dim","hold":1.6,"sfx":"page"}`

### dialogue
`{"type":"dialogue","bg":"bg_room_night","lines":[行...]}`

行字段：
| 字段 | 说明 |
|---|---|
| `who` | `data/story/characters.json` 里的 id：kurumi / mochiko / mebuki / yasuko / ikuo / kozue / narrator / tv / note |
| `face` | 表情，对应 `assets/sprites/portraits/<who>_<face>.png`；缺图退回 normal，再缺用占位剪影 |
| `text` | 台词（支持 BBCode） |
| `name` | 覆盖显示名。**没有立绘的新角色用 `"who":"narrator","name":"いなご"`**，不要发明新 id |
| `side` | left / right（默认久留美在左，其他人在右） |
| `bg` | 这一行开始切换背景 |
| `sfx` | 播放音效（`assets/sfx/<name>.wav`） |
| `hide_portrait` / `clear_portraits` | 不显示立绘 / 清空两侧立绘 |

可用表情：kurumi: normal happy smug focus worried shock cry angry tilt sleep young；mochiko: normal smile blush；
mebuki: normal happy cry；yasuko: normal angry happy；ikuo: normal angry；kozue: normal。
可用背景：`assets/sprites/bg/` 下的文件名（不含 .png），也可以用 `assets/sprites/cg/` 里的 CG。

### cg
`{"type":"cg","image":"cg_shock","lines":[...]}`（没有 lines 时显示一个继续按钮）

### unlock
`{"type":"unlock","title":"解锁！","text":"BBCode 说明","unlocks":["friend_yasuko"],"tutorial_done":false}`

### trade（交易场景：教学 / 剧情战役 / 回放）
| 字段 | 说明 |
|---|---|
| `config` | TradeSession 配置（见 §3） |
| `mods` | 本场景的能力开关，如 `{"show_sentiment":1,"stopout_delta":10}`（键见 data-reference.md §5） |
| `positions` | 预置持仓 `[{"symbol","side":1/-1,"lots","entry","sl","tp"}]`；`entry` 是绝对开仓价，要和 `config.overrides.start_prices` 一起设计（开局含み損 = 两者之差） |
| `intro` | 开场对话行（开始前播放） |
| `steps` | 教学/剧情步骤（见 §4）；没有 steps 时玩家可自由交易到时间结束 |
| `speed` | 开场速度（默认 0 = 暂停） |
| `win` | 胜利判定：`{"always":true}` / `{"steps":true}`（所有步骤完成）/ `{"equity":X}` / `{"profit":X}` / `{"no_debt":true}`；`allow_bust:true` 允许资金耗尽也算赢 |
| `lose_continues` | 失败也继续剧情（剧情注定失败的战役用 true） |
| `on_win` / `on_lose` | 结束后的对话行 |
| `close_at_end` | 结束时自动平仓（默认 true；回放类可设 false） |
| `battle` / `battle_title` | 列入「经典战役」/ 战役菜单里显示的标题 |
| `bgm_danger` | 暴走或维持率低于告警线时临时覆盖的曲子，默认 `trade_danger`；`""` 关闭（回放、剧情注定的战役）。也可写在章节顶层作为默认 |
| `bgm_peg_break` | 下限撤销（`peg_broken`）后切换的基础曲，如第 11 章 `snb_shock`；切换后不再触发危机覆盖 |

结束流程：显示结算 → 播 on_win/on_lose → 胜利或 `lose_continues` 时进入下一场景，否则出现「再来一次 / 返回章节选择」。

## 3. config（TradeSession 配置）
| 键 | 默认 | 说明 |
|---|---|---|
| `seed` | 随机 | 固定种子 = 每次行情一样（剧情建议固定） |
| `start_date` | 2014-02-03 | 第一个交易日（自动挪到工作日） |
| `days` | 3 | 交易日数（1 天 = 96 tick，从东京 07:00 开始） |
| `warmup_days` | 5 | 预热天数（只为图表有历史） |
| `balance` / `credit` | 300000 / 0 | 初始资金 / 赠金 |
| `broker` | 国内25倍 | 业者参数，字段同 `data/run/brokers.json` |
| `symbols` | USDJPY,EURJPY,AUDJPY | 报价列表（第一个为默认选中） |
| `act` | 1 | 随机新闻按哪一幕抽取 |
| `market_params` / `event_params` | | 覆盖行情/事件参数（`trend_mult`, `vol_mult`, `hunt_prob`, `intervention`, `news_per_day`, `indicator_mult`, `min_indicators_week`…） |
| `random_news` / `sns` / `calendar` / `affi` | true/true/true/false | 随机新闻、SNS、自动排经济日历、あふぃちゃん博客 |
| `overrides` | | `start_prices{symbol: 价格}`（预热后校准，历史等比缩放）、`pegs{symbol: 下限}`、`units{code: {字段: 值}}` |
| `mental` | 80 | 久留美起始メンタル |
| `goal` | | `equity`（只用于显示）、`equity_early`（净值达到即提前结束，原因 goal） |
| `goal_text` | | 顶栏右侧的目标文字 |
| `end_on_bust` / `end_on_broken` | true / true | 资金 < 1000円 且无持仓 / メンタル归零 时提前结束 |
| `script` | | 时间线（见下） |

### 时间线条目（`config.script` 与步骤 `script`）
时间：`{"day": 交易日序号, "hour": 时, "minute": 分}`（东京时间），或 `{"t": tick}`。
- 在 `config.script` 里，`t` 相对**场景开始**；
- 在步骤 `script` 里，`t` 相对**该步骤开始**，`t ≤ 0` 的条目**立即执行**。

| `do` | 参数 | 作用 |
|---|---|---|
| `news` | `def{...}` 或 `template` | 触发新闻（模板字段同 news.json） |
| `text` | `title, kind, icon, severity` | 只发一条新闻文字，不影响价格 |
| `sns` | `who, text` | 发一条 SNS |
| `guide` | `symbol, price, ticks` | 布朗桥：在 ticks 内把价格引到目标（复刻真实价位用） |
| `effect` | `target, channel, mag, delay, ramp, dur, fade, tag` | 直接加一个行情效果（字段同 news effects） |
| `peg` | `symbol, floor` | 设置汇率下限 |
| `peg_break` | `symbol, magnitude, overshoot, recover` | 撤销下限（报价货币一次性升值 magnitude×(1+overshoot)，再回吐 overshoot 部分） |
| `halt` | `symbol, on` | 报价停止/恢复（停止期间无法成交、止损和强平都会延后到恢复时） |
| `params` | `market{}, events{}` | 中途改行情/事件参数 |
| `indicator` | `id, day, forced{forecast, actual, previous, surprise, hint}` | 强制安排一个经济指标（只给 `surprise` 时会反推实际值） |
| `rate` | `unit, value` | 改政策利率 |
| `deposit` | `amount, note` | 入金（剧情：挪用存款等） |
| `mental` | `value` | 增减メンタル |
| `say` | `text, face` | 久留美的气泡台词 |
| `dialog` | `lines[]` | 打开对话框（时间暂停，关闭后自动播放段会恢复速度） |
| `pause` | `text` | 暂停并显示说明（**自动播放段不要用无 text 的 pause**） |
| `finish` | `reason` | 立即结束交易 |
| 界面动作 | | `lock{names}` `unlock{names}` `objective{text}` `highlight{name}` `select{symbol}` `tf{index:0~3}` `speed{value}` `shake{amount}` `flash{color}` `sfx{name}` |

## 4. 步骤（steps）
步骤按顺序执行；一步开始时依次：解锁/加锁 → 执行 script → 设置手数/选中品种 → 显示目标文字 → 播 `dialog` → 弹 `msg` → 高亮 → 设定 `speed`；然后等待 `until` 条件满足进入下一步。

| 字段 | 说明 |
|---|---|
| `dialog` | 对话行 |
| `msg` | BBCode 说明框（玩家点「明白了」继续） |
| `objective` | 左上角目标文字（BBCode） |
| `lock` / `unlock` | 控件名：`buy sell close speed lots sl tp tabs watch close_all close_symbol account` |
| `highlight` | 闪烁一个控件 |
| `script` | 时间线条目（`t` 相对本步） |
| `lots` / `select` | 预设手数 / 选中品种 |
| `speed` | 设定速度 0~4（强制，不受锁定限制） |
| `until` | 完成条件（缺省 = 立即完成） |
| `finish` | 这一步完成后结束交易（最后一步写 `{"finish": true}`） |

### until 条件
| type | 参数 | 满足条件 |
|---|---|---|
| `open` | `side`, `symbol`, `min_lots`, `with_sl`, `with_tp` | 本步内开了符合条件的仓 |
| `close` | `profit` | 本步内有平仓（profit=true 要求盈利） |
| `flat` | | 没有持仓 |
| `sl_set` / `tp_set` | | 有持仓设了止损/止盈 |
| `pips_sl` / `pips_tp` | | 下单面板设了止损/止盈 pips |
| `equity` | `value` | 净值 ≥ value |
| `ticks` | `n` | 本步开始后经过 n tick |
| `time` | `day, hour, minute` | 到达某交易日某时刻 |
| `tab` | `index` | 打开了第 index 个信息页（0 持仓 1 日历 2 新闻 3 FX民 4 成交） |
| `speed_any` | | 时间在流动 |
| `positions` | `n` | 持仓数 ≥ n |
| `margin_below` | `level` | 维持率 < level% |
| `any` / `all` | `of: [条件...]` | 任一 / 全部满足（例：`{"type":"any","of":[{"type":"equity","value":6400000},{"type":"time","day":1,"hour":15}]}`） |
| `manual` | | 永不自动满足 |

### 自动播放段（只让玩家看的回放/战役）
做法：在步骤里 `lock` 掉 `speed`（以及买卖/平仓），并用 `speed` 设定播放速度，`until` 用 `time` 或 `ticks`，最后 `finish`。
- 速度被锁定时，系统的自动暂停（重大新闻、指标前、维持率告警、强平）**不会触发**；对话框/说明框关闭后会**恢复原速度**。
  （这是 2026-10 修过的卡死 bug，见 CHANGELOG。）
- 目标文字里写明「自动播放中，无需操作」，玩家才不会以为卡住。
- 新增这类场景后，把章节加进 `tests/autoplay_check.gd` 的 `CHAPTERS` 列表跑一遍。

### 要玩家操作的教学步
- 有 `until` 等玩家操作时，**不要**把 `buy/sell/close` 中玩家需要的那个锁住。
- 有时间限制的目标用 `any` 组合一个 `time`，避免玩家没达成时后续剧情永远不触发（参考 ch09）。
- 预置持仓离强平线要留足缓冲：一根 15 分钟 K 线的正常波动就可能打穿（参考 ch04 用 `stopout_delta`）。

## 5. 新增/修改章节后的检查
```bash
G=D:/godot/Godot_v4.7.2-stable_win64_console.exe
cd projects/kurumi-fx-rogue
$G --headless --path . res://tests/compile_check.tscn                       # JSON 能解析
$G --path . res://tests/tutorial_driver.tscn -- --chapter=ch16               # 模拟玩家走完所有步骤
$G --path . res://tests/autoplay_check.tscn                                  # 自动播放段不会卡住（先把章节加进 CHAPTERS）
$G --headless --path . res://tests/check_battle.tscn -- --chapter=ch16       # 无界面跑交易场景，打印最低价/收盘/不足金等关键数字
$G --path . res://src/story/story_player.tscn -- --chapter=ch16 --scene-index=2 --shot=<绝对路径.png> --shot-delay=3   # 截图
```
`check_battle` 适合核对复刻战役的数字是否与原作/报道一致（例：ch11 瑞郎冲击实测最低 0.853、收盘 1.055、不足金约 1.22 億）。

## 6. 最小骨架
```json
{
 "id": "ch16", "order": 16, "title": "第16章 ……", "manga": "第54〜56話", "period": "2017年",
 "source": "manga-reference.md §3.1 第54〜56話（来源编号…）",
 "original": "交易场景的行情与资金为游戏设定；台词为转述。",
 "requires": ["ch15"],
 "scenes": [
  {"type": "title_card", "text": "第16章", "sub": "……"},
  {"type": "dialogue", "bg": "bg_office", "lines": [
   {"who": "kurumi", "face": "normal", "text": "……"},
   {"who": "narrator", "name": "きずな", "text": "……"}
  ]},
  {"type": "trade",
   "config": {"seed": 20170501, "start_date": "2017-05-01", "days": 2, "balance": 50000,
              "broker": {"name": "国内FX", "leverage": 25, "stopout": 100, "margin_call": 150, "zero_cut": false},
              "symbols": ["EURUSD", "USDJPY"], "act": 1},
   "steps": [
    {"lock": ["close", "speed"], "objective": "开一单", "until": {"type": "open"}},
    {"unlock": ["close", "speed"], "speed": 1, "objective": "观察", "until": {"type": "time", "day": 1, "hour": 15}},
    {"finish": true}
   ],
   "win": {"always": true}, "lose_continues": true}
 ]
}
```
