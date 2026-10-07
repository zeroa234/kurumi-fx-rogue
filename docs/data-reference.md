# 数据字段参考（data/ 与 config/）

所有内容数据都是 JSON，由 `DB.get_json(path)` 读取并缓存（`src/core/db.gd`）。改完数据跑一次
`tests/compile_check.tscn`，它会逐个解析下面列出的文件。

> 约定
> - JSON 里的数字在 GDScript 中都是 **float**。代码里比较整数时要先转换（例：`acts` 用 `has(float(act))`）。
> - 每个文件顶部的 `_doc` 字段是给人看的说明，代码不读。
> - 「未使用」= 字段已在数据里，但当前代码没有读取（见 `docs/maintenance.md` 已知问题）。

---

## 1. 行情 `data/market/`

### units.json → `units[]`（货币 / 资产单元）
价格模型：品种价格 = `anchor(base)/anchor(quote) × exp(有效强度差 + 品种偏移)`，有效强度 = `x + Σ β·因子`。

| 字段 | 类型 | 说明 |
|---|---|---|
| `code` | str | 单元代码（JPY/USD/EUR/GBP/AUD/CHF/TRY/N225/XAU），被品种、事件 target 引用 |
| `name` | str | 中文名（新闻标题 `$N` 替换用） |
| `anchor_jpy` | float | x=0 时 1 单位折合日元，决定初始价位 |
| `vol` | float | 日波动（对数）。品种日波动 ≈ √(vol_base² + vol_quote²) |
| `betas` | dict | 对公共因子的暴露 `{"risk": .., "usd": .., "commod": ..}` |
| `rate` | float | 政策利率 %（掉期计算；利率决议/央行事件会改它） |
| `carry` | float | 每日长期漂移（负数 = 长期贬值，如 TRY） |
| `mr` | float | 向公允价值回归的日速度 |
| `trend` | float | 趋势 regime 时的日漂移（以 vol 为单位），再乘幕参数 `trend_mult` |
| `jump_rate` / `jump` | float | 每日自发跳跃次数期望 / 跳跃对数标准差 |

### units.json → `factors[]`（公共因子，OU 过程）
`id`（risk/usd/commod）、`name`、`theta`（日回归速度）、`vol`（日波动）。

### instruments.json → `instruments[]`（可交易品种）
| 字段 | 说明 |
|---|---|
| `symbol` | 品种代码，如 `USDJPY`（剧情/事件用 `pair:USDJPY` 引用） |
| `name` | 中文名 |
| `base` / `quote` | 单元代码 |
| `kind` | fx / index / metal（目前只用于显示） |
| `digits` / `pip` | 显示小数位 / 1 pip 的价格单位 |
| `spread` | 基础点差（pips），再乘时段曲线、事件、业者、手法倍率 |
| `contract` | 1 枚的基础货币数量（FX = 10000） |
| `unlock` | 空 = 默认可交易；否则需要该解锁标签（局外养成或业者 `grant`） |

---

## 2. 事件 `data/events/`

### indicators.json → `indicators[]`（经济日历）
| 字段 | 说明 |
|---|---|
| `id`, `name`, `unit` | `unit` 为受影响的单元代码 |
| `stars` | 重要度 1~3；≥2 时发布前自动暂停（设置可关） |
| `weekday`, `hour`, `minute` | 东京时间。07:00 以前发布的算前一个交易日 |
| `chance` | 每周出现概率（`min_indicators_week` 会补足最低数量） |
| `fmt` | 数值格式（GDScript `%` 格式串） |
| `mean`, `sd`, `surprise_sd` | 预测 = mean+N(0,sd·0.8)；实际 = 预测 + N(0,surprise_sd) |
| `good` | 1 = 数值高利好该货币；-1 = 相反（如通胀） |
| `sens` | 冲击 = sens × z（z = 惊喜 / surprise_sd × good，截断 ±4） |
| `risk` | 同时作用在风险偏好因子上的系数 |
| `kind: "rate"` + `step` | 利率决议：结果为 加息/维持/降息 一个 step；发布后改写单元 `rate` |

### news.json → `news[]`（随机新闻 / 灾害 / 谣言模板，也可被剧情和 Boss 按 id 调用）
| 字段 | 说明 |
|---|---|
| `id` | 模板 id（`{"do":"news","template":"flash_crash"}` 引用） |
| `kind` | news / disaster / politics / speech / rumor / cb / market（决定颜色、速报、久留美台词 `news_<kind>`） |
| `icon` | `src/ui/pixel_icons.gd` 里的 ASCII 图标 id |
| `weight`, `acts` | 随机抽取权重；出现在哪几幕 |
| `title` / `body` | 文本；`$N` = 随机选中货币的中文名 |
| `pool` | 随机货币池；effects 里 `$C` 替换为选中的货币代码 |
| `sign: "random"` + `title_up/title_down` | 方向随机：level/drift 乘 ±1，regime 1↔2 互换 |
| `credibility` + `denial` | 谣言为真的概率；为假时价格冲击会完全回吐，并在之后发「辟谣」新闻 |
| `rate_change` | 同时改选中货币的政策利率 |
| `early_morning` | 只在东京 05:00~08:00 出现（闪崩） |
| `severity` | 可选，1~3；≥3 或 disaster/cb 会弹「速報」 |
| `delay`, `instant` | 可选：效果延迟（默认 2 tick）/ 标题立即显示 |
| `peg_break` | 可选：`{"symbol","magnitude","overshoot","recover"}` 触发钉住撤销 |

`effects[]`：
| 字段 | 说明 |
|---|---|
| `target` | 单元代码 / `factor:risk|usd|commod` / `pair:<symbol>`（只动该品种）/ `*`（所有，仅 vol/spread） |
| `channel` | `level` 价格冲击（对数）· `drift` 日漂移 · `vol` 波动倍率 · `jump` 跳跃频率倍率 · `spread` 点差倍率 · `regime` 强制趋势（1 多头 2 空头）· `fair` 公允价值平移 |
| `mag` | 幅度（随机新闻会再乘 0.6~1.4 与 `news_scale`） |
| `ramp` | 爬升 tick 数（level 用平滑曲线） |
| `dur` | 持续 tick 数（level 为回吐时长） |
| `fade` | level 在 dur 内回吐的比例（0 = 永久，1 = 全部吐回） |
| `delay` | 额外延迟 |

### sns.json
`handles[]` 虚构账号；`contexts{}` 按情境的发言模板（`{sym}` 品种名、`{p}` 价格）：
up_strong / down_strong / range / crowd_long / crowd_short / event / idle 由代码选择；
**loss / win 目前未被代码使用**。`affi[]` 是あふぃちゃん（やす子同行时）的博客文。

---

## 3. 剧情 `data/story/`

- `chapters/*.json`：章节，格式见 `docs/story-format.md`。
- `characters.json` → `characters{id: {name, color, hair}}`：对话名牌颜色、缺图时占位剪影的发色。
  对话里 `who` 必须是这里的 id；临时人物用 `"who":"narrator","name":"显示名"`。
- `barks.json`：交易中久留美的台词，键 → `[{t: 台词, f: 表情}]`。
  代码使用的键：open_long, open_short, win_small, win_big, loss_small, loss_big, margin_call, stop_out,
  float_up, float_down, news, indicator, idle, tilt, swap, zero_cut, news_disaster, news_cb, news_rumor,
  news_denial, news_politics, news_market, news_speech, flash_crash, peg_break, intervention,
  indicator_big, indicator_flat, mebuki_call。**`hunt` 目前未被代码使用。**

---

## 4. 肉鸽 `data/run/`

### brokers.json → `brokers[]`
| 字段 | 说明 |
|---|---|
| `id`, `name`, `desc` | |
| `leverage` | 杠杆倍数（再乘 `leverage_mult`） |
| `stopout` / `margin_call` | 强平 / 告警维持率 % |
| `zero_cut` | 负余额是否清零；false 时负余额变成「不足金」（借金） |
| `spread_mult`, `slip_mult` | 点差、滑点倍率 |
| `swap_mult`, `swap_fee` | 掉期倍率、业者抽成（年化名义比例） |
| `bonus` | 每幕第一个交易节点赠送「资金×bonus」的赠金（可作保证金，不可出金） |
| `unlock` | 解锁标签（空 = 默认） |
| `grant` | 选用此业者时额外开放的品种解锁标签 |

### relics.json → `relics[]`（手法，局内永久）
`id`, `name`, `rarity`（common/uncommon/rare → 商店价 55/90/150 FP、出现权重 6/3/1）, `tag`（info/risk/gamble/swap/news/econ），
`icon`（`assets/sprites/icons/<icon>.png`）, `desc`, `mods`（叠加到 Mods，见下表）, `unlock`（需要的解锁标签）。

### items.json
`items[]`：`id, name, icon, price, use(map|trade|both), desc, shop(false=商店不卖), effect{}`。
`effect` 可用键：`mental`, `cure_tilt`（メンタル至少回到该值）, `money_flat`, `curse`, `loan_ratio`,
`temp_mods`（下一个交易节点生效）, `skip_node`。交易中只处理 `mental`/`cure_tilt`（`src/run/run_trade.gd`）。

`curses[]`：`id, name, icon, desc, mods`。特殊效果写在代码里：`posipos`（`run_trade.gd` 每天空仓 −6）、
`tax`（`RunState.settle_trade` 扣节点盈利 20%）。

### friends.json → `friends[]`（仲间）
`id, name, unlock, color, bio, passive_desc, passive(mods), special, active{id,name,charges,desc}`。
主动/特殊能力的效果写在 `src/run/run_trade.gd`（`_use_friend`、`_mebuki_prophecy`、`_on_day`），新增仲间要同时改代码。

### nodes.json
- `acts[]`：`act, name, target`（Boss 结束时净资产目标）, `start_date`, `days_trade`, `days_boss`,
  `market{}`（覆盖 MarketSim.params）, `events{}`（覆盖 EventEngine.params）, `goal_pct`（普通相場的奖励目标）。
- `endless`：`target_mult`（第 4 幕起每幕目标倍率）, `vol_step`（每幕 vol_mult 增量）。
- `elites[]`：`id, name, desc, market{}, events{}, mult`（true = 与幕参数相乘，否则覆盖）, `script[]`, `symbols_add[]`。
- `bosses[]`：`id, act, name, desc, market{}, events{}, script[], pegs{}, start_prices{}, symbols_add[]`。
  **`intervene_prob` 目前未被代码使用**（干预概率在 `MarketSim._maybe_intervene` 里写死）。

Boss/精英 `script[]` 条目同剧情时间线（见 story-format.md），额外支持：
`rand_day: [a,b]`（随机交易日）、`indicator` 的 `forced_surprise`（随机正负号的惊喜值）、
`do: "peg_break_news"`（发速报并撤销 EUR/CHF 下限，幅度随机 0.18~0.30）。

### events.json → `events[]`（地图上的文字事件）
`id, title, bg, who, face, acts, text, requires_friend, choices[]`；`choice = {text, effects, req}`。
`effects` 可用键：`mental, fp, money_act`（×幕基数 5万/20万/80万/300万 × 打工倍率）, `money_pct`, `loan_pct`,
`relic`（`random` / `random_info` / `random_risk` / `random_chart` / `random_rare` / 具体 id）, `item`, `curse`,
`remove_curse`, `gamble{chance, win{}, lose{}}`。`req`：`fp`（至少多少 FP）, `money_pct_min`。

### meta.json
- `nodes[]`（局外养成）：`id, name, desc, cost[]`（每级价格，长度 = 最大等级）, `requires[]`, `effect{}`：
  `start_money`（每级 +円）· `mods`（每级叠加；*_mult 按级数取幂）· `unlock`（标签）· `special`（代码实现：
  `item_slot`, `friend_slot`, `free_reroll`, `start_relic`, `first_stopout_refund`）。
- `ascension[]`：挑战度说明文字；实际效果写在 `RunState`（`target()`、`create()`、`rebuild_mods()`、`trade_config()`、`_gen_map()`、`next_act()`）。

---

## 5. Mods 修正值键（`src/core/mods.gd`）

规则：键名以 `_mult` 结尾的各层**相乘**，其余**相加**。来源层：局外养成、手法、仲间被动、诅咒、挑战度、道具临时层、仲间主动临时层。

| 键 | 默认 | 作用位置 |
|---|---|---|
| leverage_mult, spread_mult, swap_mult, sl_slip_mult, max_lot_mult | 1 | Account |
| profit_mult, loss_mult | 1 | Account 平仓损益 |
| trend_profit, event_profit | 0 | 顺隐藏趋势平仓 / 事件后 8 tick 内开仓的盈利加成 |
| nanpin | 0 | 逆向加仓成交价改善比例 |
| insurance | 0 | 每天第一笔亏损返还比例 |
| zero_cut | 0 | >0 时下一次负余额清零（用掉一次） |
| stopout_delta | 0 | 强平线下调（百分点） |
| max_positions | 3 | 同时持仓数 |
| trailing | 0 | 追踪止损按钮可用 |
| mental_loss_mult, mental_gain_mult, mental_max(100), mental_regen, tilt_resist | | Kurumi |
| news_lead, forecast_acc, calendar_days(1) | | EventEngine / 日历页 |
| show_fair, show_clusters, show_sentiment, show_trend, ind_ma, ind_bb, ind_rsi | 0 | ChartView 显示 |
| fp_mult, work_pay_mult, shop_discount | | RunState / 地图 |
| swap_reinvest | 0 | **未实现**（无代码读取） |

---

## 5.5 BGM 清单 `config/bgm-cues.json`
由 `scripts/gen_bgm.py` 读取，详见 `docs/bgm.md`。
| 键 | 说明 |
|---|---|
| `defaults` | 每个 YuE2 `generate` 请求的公共字段（`instrumental:true`、`cot:"off"`、显存参数等） |
| `style_prefix` / `style_suffix` | 拼在每首 `style` 前 / 后（后缀是引导长编曲的描述） |
| `lyrics` | 歌词（instrumental 模式下服务端一律换成 `[instrumental]`） |
| `separate` | true 时 `post` 改用 demucs 去人声伴奏（`output/bgm/inst/`）；当前 false |
| `post` | 后期：目标响度 `lufs`、`true_peak`、淡入淡出秒数、`max_seconds`、OGG 质量、采样率 |
| `cues[]` | `id`（= `assets/bgm/<id>.ogg`）、`label`、`uses`（说明）、`style`、`seed`；可选 `request`（覆盖请求字段）、`lyrics` |

成品记录 `assets/bgm/index.json` → `tracks{id: {label, uses, style, job_id, seed, raw_seconds, seconds, input_lufs, qa, …}}`。

## 6. 素材清单 `config/asset-manifest.json`

见 `docs/art-pipeline.md`。`kinds{}` 定义每类素材的生成模板、像素尺寸、颜色数、抠图方式；
`assets[]` 每项：`id, kind, label, seed, tags, nl, ref`（IC 参考角色）, `negativeExtra`, `kind_override`, `via`（备注）。

## 7. 存档 `user://save.json`（`src/core/save.gd`）

Windows 路径：`%APPDATA%\Godot\app_userdata\FX战士久留美 同人 · 2000万之路\save.json`。

| 键 | 内容 |
|---|---|
| `story` | `cleared[]` 已读章节、`tutorial_done`、`current`（未使用） |
| `meta` | `points`, `total_points`, `levels{id: 等级}`, `unlocks[]`（解锁标签）, `max_ascension` |
| `stats` | `runs, clears, best_equity, total_trades, deaths{原因: 次数}` |
| `codex` | `relics, items, events, bosses` 已发现 id |
| `settings` | `speed, auto_pause_news, auto_pause_indicator, auto_pause_margin, screen_shake, green_up, sfx, bgm`（音乐音量 0~1，默认 0.6，BGM 与开场 PV 共用）、`opening_every_launch`；`fullscreen` 未使用（F11 直接切换） |
| `run` | 进行中的肉鸽局，`RunState.to_dict()`；为空表示没有进行中的局 |

读档时 `_merge` 会把新版本默认值补进旧存档，所以**新增键要先加到 `_default()`**。

解锁标签一览：`roguelike`, `friend_mochiko`, `friend_mebuki`, `friend_yasuko`, `pair_eurchf`, `pair_tryjpy`,
`pair_n225`, `pair_xauusd`, `broker_swap`, `broker_pro`, `pool_info`, `pool_gamble`。
