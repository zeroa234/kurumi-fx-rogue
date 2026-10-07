# 背景音乐（BGM）

> **状态：接入已完成；24 首正在生成（2026-10-07）**。进度见文末「§6 进度」。

所有 BGM 由本地 **YuE2-T8**（`D:\YuE2-T8-Local-v1.4.17-CSD-Trained-20260915`，服务 `http://127.0.0.1:8189`，版本 1.6.9）以**纯器乐模式**生成，
提示词写法遵循 `extensions/skills/yue2-prompt`，服务调用遵循 `extensions/skills/yue2-workbench`。

## 1. 文件
| 路径 | 内容 |
|---|---|
| `config/bgm-cues.json` | 曲目清单：每首的 id、中文名、用途、style、种子；生成默认参数；后期参数（字段见 data-reference.md §5.5） |
| `scripts/gen_bgm.py` | 管线：`status / submit / fetch [--wait] / qa / post`（说明见脚本头） |
| `scripts/bgm_qa.py` | 客观检查（用 YuE2 运行时的 demucs + librosa）：人声声部比例、节拍、静音、峰值；`--inst-dir` 另存去人声伴奏 |
| `src/ui/bgm.gd` | 游戏内播放器，自动加载 `Bgm` |
| `output/bgm/` | 作业记录 `jobs.json`、原始 `raw/*.flac`、`qa.json`、`test/`（方法对比样本）（不入库） |
| `assets/bgm/<id>.ogg` + `index.json` | 成品与来源记录（入库） |

## 2. 生成方法（已实测）
请求：`kind:"generate"`，`instrumental:true`，`cot:"off"`，`cfg_scale:1.01`，显式 `seed`，`memory_budget_gib:14`，`offload_ar:true`；
style 末尾统一加 `style_suffix`（"long extended full-length arrangement, intro, main theme, development section and reprise, about 3 minutes long"）。

`instrumental:true` 时服务端在 style 前加「Instrumental music only; no singing, no vocals, no spoken voice, no choir.」、删去 style 里的人声词、
把歌词换成 `[instrumental]`（`app/yue2_app/core_worker.py` 的 `instrumental_style()` / `generation_kwargs()`）。这只是文本引导，所以每首都要跑 `qa` 并试听。

同一首（title，种子 20261001）对比过的加长办法：
| 做法 | 时长 | 结果 |
|---|---|---|
| `instrumental:true`（原样） | 57.8 秒 | 无人声（试听 + demucs 人声声部能量≈0），但太短 |
| 不开 instrumental，自带 no-vocals 前缀 + 空乐段标签歌词 `[Intro][Verse][Chorus]…` | 147.5 秒 | **有人声**（vocal_ratio 0.11）；demucs 去掉人声声部后发糊 → 弃用 |
| `instrumental:true` + `semantic_sampling.min_tokens:3000` | 141.4 秒 | 中段 11.5 秒静音、之后出人声（vocal_ratio 0.10）——强制推迟结束 token，模型在「曲子已完」之后接着写 → 弃用 |
| `instrumental:true` + style 长编曲后缀 | 待批量结果 | 当前做法 |

经验：YuE2 每秒约 25 个语义 token；qa 的 `vocal_ratio`（demucs 人声声部能量 / 混音能量）在干净的器乐上≈0，出人声时约 0.1。
合格线（批量用）：`vocal_ratio ≤ 0.02`、`vocal_active ≤ 0.05`、`longest_gap ≤ 4` 秒；不合格换种子（+100、+200）重生。

## 3. 曲目与场景（24 首）
| id | 名称 | 用在哪里 |
|---|---|---|
| title | 主题曲 | 标题画面；第1章结尾标题卡 |
| menu | 菜单 | 章节选择、经典战役、图鉴、局外养成、肉鸽开局（设置画面沿用当前曲） |
| story_daily | 日常 | 第3、6~10章校园/咖啡店轻松对话 |
| story_night | 深夜的书桌 | 第1章结尾、第2章、第5章后半、第8章结尾 |
| story_tragedy | 失去 | 第1章母亲崩溃与离世、第13章开头 |
| story_family | 父亲的眼泪 | 第5章、第9章萌智子往事、第10章芽吹破产、第13章坦白 |
| story_ominous | 坚硬的地板 | 第1章开头、第4章开头、第10章 EUR/CHF、第11章开头与回放平静期 |
| story_hope | 下一页 | 第13章破产手续之后、2017 年 |
| story_office | もちもち企画 | 第14~15章 |
| trade_tutorial | 交易·练习 | 第2~6章教程交易、第15章新人交易 |
| trade_main | 交易·实战 | 第7~10章交易、肉鸽普通相場、调试沙盒 |
| trade_danger | 交易·危机 | **动态**：交易中暴走或维持率低于告警线时覆盖播放，恢复后切回 |
| trade_elite | 精英 | 肉鸽精英节点 |
| boss | BOSS | 肉鸽第1~2幕 Boss |
| boss_final | 最终BOSS | 肉鸽第3幕及无尽模式 Boss |
| replay_2008 | 2008年10月 | 特殊：第1章母亲的交易画面（雷曼回放） |
| snb_shock | 18:30 | 特殊：EUR/CHF 下限撤销（`peg_broken` 信号）起切换——第11章、Boss 黑色星期四 |
| last_gamble | 最后的100万円 | 特殊：第12章（标题卡起到交易结束） |
| map | 地图 | 肉鸽地图 |
| shop / rest / event | 商店 / 休息 / 事件 | 肉鸽地图上的弹窗（覆盖播放，关掉回到地图曲） |
| victory | 2000万円 | 2000万达成弹窗、通关结算 |
| gameover | 败北 | 失败结算 |

## 4. 游戏内接入（已实现）
- 自动加载 `Bgm`（`src/ui/bgm.gd`，在 `Sfx` 之后）。API：`play(id)` 换基础曲（同名不重启、交叉淡入淡出）、`overlay(id)` / `clear_overlay()` 临时覆盖（覆盖期间基础曲暂停，清除后从原处继续）、`stop()`、`apply_volume()`。缺 ogg 文件时静音、不报错。
- 音量：设置画面「音乐音量」（`settings.bgm`，默认 0.6，与开场 PV 共用），拖动即时生效。
- 场景：标题 `title`；章节选择 / 经典战役 / 图鉴 / 肉鸽开局 / 局外养成 `menu`；设置沿用当前曲；开场 PV 停掉 BGM（视频自带配乐）；调试沙盒 `trade_main`。
- 剧情：场景字段 `bgm`；`story_player._apply_bgm()` 播放第 i 个场景时向前找最近一个带 `bgm` 的场景（`--scene-index` 跳转、经典战役、重试都对）。
  交易场景另有 `bgm_danger`（默认 `trade_danger`，`""` 关闭）与 `bgm_peg_break`（格式见 story-format.md §2）。
- 交易界面（`TradeScreen._update_bgm_danger()`）：暴走或维持率 < 告警线 → `overlay(bgm_danger)`；不暴走且（无持仓或维持率 > 告警线×1.2）→ 清除；结束与离开时清除。下限撤销后若设了 `bgm_peg_break` 就换基础曲并停用危机覆盖。
- 肉鸽：地图 `map`；事件 / 商店 / 休息为覆盖曲，`_finish_node()` 清除；交易节点按类型 `trade_main` / `trade_elite` / `boss`（第 3 幕及无尽模式 `boss_final`），Boss 节点下限撤销（黑色星期四）切 `snb_shock`；通关弹窗 `victory`；结算按胜负 `victory` / `gameover`。
- 循环：成品首尾已做淡入淡出，`AudioStreamOggVorbis.loop = true` 整首循环。

### 各章配曲（`data/story/chapters/*.json` 的 `bgm`，序号 = 场景下标）
| 章 | 配曲 |
|---|---|
| ch01 | 0 story_ominous → 2 交易 replay_2008（无危机覆盖）→ 3 story_tragedy → 4 story_night → 5 标题卡 title |
| ch02 | 0 story_night → 2 trade_tutorial |
| ch03 | 0 story_daily → 2 trade_tutorial |
| ch04 | 0 story_ominous → 2 trade_tutorial（含危机覆盖） |
| ch05 | 0 story_family → 2 story_night |
| ch06 | 0 story_daily → 2 trade_tutorial |
| ch07 | 0 story_daily → 2 trade_main → 3 story_daily |
| ch08 | 0 story_daily → 2 trade_main → 3 story_night |
| ch09 | 0 story_family（萌智子往事）→ 2 trade_main → 3 story_daily |
| ch10 | 0 story_family（芽吹破产）→ 2 story_daily（やす子的漫画）→ 3 story_ominous（盯上 EUR/CHF）→ 4 trade_main → 5 story_ominous |
| ch11 | 0 story_ominous → 2 交易 story_ominous，下限撤销切 snb_shock（无危机覆盖） |
| ch12 | 0 last_gamble 直到交易结束（无危机覆盖） |
| ch13 | 0 story_tragedy → 2 story_family → 3 story_hope |
| ch14 | 0 story_office |
| ch15 | 0 story_office → 2 trade_tutorial |

## 5. 测试
接入后（尚无 ogg 时）compile_check / smoke_ui / autoplay_check / touch_check / tutorial_driver 全过。有成品后需再跑一遍并实机听切换。

## 6. 进度
- [x] 曲目规划、管线脚本、播放器、接入、文档。
- [ ] 24 首生成 → qa → post（pi 子 agent 执行中，2026-10-07 13:56 提交）。
- [ ] 有成品后：重跑测试、实机听、提交 `assets/bgm/`。
