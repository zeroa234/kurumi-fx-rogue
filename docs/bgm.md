# 背景音乐（BGM）

> **状态（2026-10-07）：游戏内现用 19 首 CC0 开源曲（OpenGameArt），24 个曲目 id 复用映射；YuE2 自制曲暂停**（加长后会出人声，见 §2）。

## 0. 现用：CC0 开源曲
- 清单 `config/bgm-oss.json`：`sources`（下载地址、作者、许可证、出处页）+ `cues`（曲目 id → source）。
- 导入 `python scripts/import_oss_bgm.py`：下载到 `output/bgm/oss/src/`（不入库）→ 只做整体增益（-18 LUFS、真峰值 ≤ -1.5 dB）→ `assets/bgm/<source>.ogg`，
  并写 `assets/bgm/tracks.json`（`cues` 映射 + `sources` 出处）。**不淡入淡出、不裁剪**，保留原曲的无缝循环。
- 播放器按 `tracks.json` 的 `cues` 找文件，没映射的 id 才找 `assets/bgm/<id>.ogg`（YuE2 管线的产出）。
  以后要换成自制曲：把该 id 从 `bgm-oss.json` 的 `cues` 删掉并重跑导入，再放 `<id>.ogg`。
- 不同 id 共用同一首时，切换不会重头播放（如第 1 章 story_ominous → replay_2008）。
- 选曲依据：原作者的描述/标签 + qa 测得的速度（`output/bgm/oss/qa.json`），**未经人耳逐首确认**，需要试听后调整映射。
- MP3 来源的曲子解码后首尾可能有几十毫秒编码器填充，循环点可能有轻微停顿（待试听）。

| 曲目 id | 曲子 | 作者 | 时长 |
|---|---|---|---|
| title | Stage 1（Chiptune Adventures） | Juhani Junkala | 41 s |
| menu、event | Stage Select（Chiptune Adventures） | Juhani Junkala | 21 s |
| map | Stage 2（Chiptune Adventures） | Juhani Junkala | 56 s |
| boss | Boss Fight（Chiptune Adventures） | Juhani Junkala | 72 s |
| trade_main | Level 1（Retro Game Music Pack） | Juhani Junkala | 74 s |
| trade_elite | Level 2（Retro Game Music Pack） | Juhani Junkala | 73 s |
| trade_tutorial | Level 3（Retro Game Music Pack） | Juhani Junkala | 82 s |
| shop | Title Screen（Retro Game Music Pack） | Juhani Junkala | 11 s |
| victory | Ending（Retro Game Music Pack） | Juhani Junkala | 45 s |
| boss_final | 8-bit Danger!! Strong Boss | HydroGene | 134 s |
| trade_danger | Tension | tapatilorenzo | 51 s |
| snb_shock | tension and distress | Allen Yatsura | 121 s |
| last_gamble | Tension Theme | Umplix | 43 s |
| story_ominous、replay_2008 | Contemplation | Joth | 120 s |
| story_family | Eye of the Storm | Joth | 46 s |
| story_night、rest | JRPG Piano | Joth | 25 s |
| story_tragedy、gameover | Emotional Piano Loop | extenz | 28 s |
| story_hope | Piano & Drums, positive melancholy | Dizzy Crow | 64 s |
| story_daily、story_office | Happy Clappy Loop | OwlishMedia | 17 s |

出处页见 `config/bgm-oss.json` 的 `page`。全部 CC0 1.0（公有领域，无需署名），仍在此与 README 致谢。

---
以下为 YuE2 自制管线（暂停）。由本地 **YuE2-T8**（`D:\YuE2-T8-Local-v1.4.17-CSD-Trained-20260915`，服务 `http://127.0.0.1:8189`，版本 1.6.9）以**纯器乐模式**生成，
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
| `instrumental:true` + style 长编曲后缀（"long extended full-length arrangement, intro, main theme, development section and reprise, about 3 minutes long"） | 210.9 秒（自然结束） | vocal_ratio 0.26、vocal_active 0.51，疑似有人声（未逐段确认）→ 批量已取消 |

结论：迄今只有原样（约 58 秒）的结果是干净的；凡是让曲子变长的做法都出了人声。待查：人声是否集中在 ~60 秒之后（区分「长度本身」与「后缀用词」两种原因）。

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
`tests/bgm_check.tscn`（headless，不写存档）：每个曲目 id 都能找到并加载成循环 OGG、章节里引用的 id 都在清单里、play/overlay/clear/stop 与共用文件的状态切换 → `BGM CHECK: 0 failures`。
导入开源曲后 compile_check / test_market / test_save / smoke_ui / autoplay_check / touch_check / tutorial_driver / opening_check 全过。尚未实机试听各场景切换。

## 6. 进度
- [x] 曲目规划、管线脚本、播放器、接入、文档。
- [x] 开源 CC0 曲导入并接入（19 首）。
- [ ] 试听开源曲与各场景是否搭配，调整 `bgm-oss.json` 的 `cues`。
- [ ] YuE2 自制曲：批量（带长编曲后缀）已于 14:05 取消，只有 title 生成完（`output/bgm/listen/title.flac`，疑似人声）；需先查清加长与人声的关系再继续。
