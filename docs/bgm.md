# 背景音乐（BGM）

> **状态：进行中（2026-10-06 暂停，等额度恢复后继续）**。进度与下一步见文末「§5 进度」。

所有 BGM 由本地 **YuE2-T8**（`D:\YuE2-T8-Local-v1.4.17-CSD-Trained-20260915`，服务 `http://127.0.0.1:8189`，版本 1.6.9）以**纯器乐模式**生成，
提示词写法遵循 `extensions/skills/yue2-prompt`，服务调用遵循 `extensions/skills/yue2-workbench`。

## 1. 文件
| 路径 | 内容 |
|---|---|
| `config/bgm-cues.json` | 曲目清单：每首的 id、中文名、用途、style、种子；生成默认参数；后期参数 |
| `scripts/gen_bgm.py` | 管线：`status / submit / fetch / post / qa`（说明见脚本头） |
| `scripts/bgm_qa.py` | 客观检查（用 YuE2 运行时的 demucs + librosa）：人声残留比、节拍、静音、峰值 |
| `src/ui/bgm.gd` | 游戏内播放器（**已写好，尚未注册为自动加载、尚未接入各场景**） |
| `output/bgm/` | 作业记录 `jobs.json`、原始 `raw/*.flac`、`qa.json`（不入库） |
| `assets/bgm/<id>.ogg` + `index.json` | 成品与来源记录（入库）——**尚未生成** |

## 2. 生成参数（已核实）
- 请求：`kind:"generate"`，`instrumental:true`，`cot:"off"`，`cfg_scale:1.01`，显式 `seed`，`memory_budget_gib:14`（ComfyUI 同时占着约 5 GB 显存），`offload_ar:true`。
- 1.6.9 的 `instrumental:true` 会在服务端把 style 前加「Instrumental music only; no singing, no vocals, no spoken voice, no choir.」，
  并删去 style 里的人声词、把歌词换成 `[instrumental]`（`app/yue2_app/core_worker.py` 的 `instrumental_style()` / `generation_kwargs()`）。
  这只是文本引导，**不保证没有人声**，所以要跑 `qa` 并试听。
- style 里不要写 choir / vocal / voice 之类的词（会被删掉，或者反而引出人声）。
- 以往同机纯器乐作业约 200 秒、生成约 4 分钟/首（参考作业 `20260918-224456-872fc286`）。当前版本下的时长待第一首测试确认。

## 3. 曲目与场景（计划，24 首）
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

## 4. 接入设计（待实现）
- `src/ui/bgm.gd` 注册为自动加载 `Bgm`（放在 `Sfx` 之后）。API：`play(id)` 换基础曲（同名不重启）、`overlay(id)` / `clear_overlay()` 临时覆盖、`stop()`、`apply_volume()`。
- 设置：`Save._default().settings` 加 `bgm: 0.6`；设置画面加「音乐音量」滑条（改后调用 `Bgm.apply_volume()`）。
- 剧情：场景加可选字段 `bgm`；`story_player` 播放第 i 个场景时向前找最近一个带 `bgm` 的场景并 `Bgm.play()`（这样 `--scene-index` 跳转和经典战役也对）。
  交易场景另有 `bgm_danger`（默认 `trade_danger`，`""` 关闭）与 `bgm_peg_break`（下限撤销后切换的曲）。第1、11、12章关闭危机覆盖。
- 交易界面：暴走或维持率 < 告警线 → `overlay(bgm_danger)`；不暴走且维持率 > 告警线×1.2 或无持仓 → `clear_overlay()`；结束和 `_exit_tree` 时清除覆盖。
- 肉鸽：`run_trade` 按节点类型选曲（black_thursday 加 `snb_shock`）；`run_map` 播 `map`，事件/商店/休息用覆盖，`_finish_node` 清除；`_victory` 播 `victory`；`run_result` 按胜负。
- 循环：成品首尾已做淡入淡出，`AudioStreamOggVorbis.loop = true` 整首循环。
- 文档同步：story-format.md（`bgm` 字段）、data-reference.md（设置键、bgm-cues.json）、maintenance.md（自动加载顺序、加/换曲流程）、README、CHANGELOG。

## 5. 进度
已完成：
- [x] 读完 docs/、全部章节场景，按场景情绪定出 24 首曲目与使用位置（§3）。
- [x] `config/bgm-cues.json`（全部 24 条 style/种子）。
- [x] `scripts/gen_bgm.py`、`scripts/bgm_qa.py`（**尚未实际运行过**，首次使用时注意排错）。
- [x] `src/ui/bgm.gd`（未注册、未测试）。
- [x] 提交第一首测试：`title`，作业 `20261006-223920-e74f29de`，seed 20261001（通过 MCP 提交，未写入 `output/bgm/jobs.json`）。

下一步：
1. 查测试作业结果（`yue2_jobs get 20261006-223920-e74f29de`）：时长、`truncated`；把它补进 `output/bgm/jobs.json`，或直接 `python scripts/gen_bgm.py submit title` 重新走脚本。
2. `python scripts/gen_bgm.py fetch title` → `qa title` → 试听确认无人声、风格对，再 `submit` 其余 23 首（服务端排队顺序执行，约 4~5 分钟/首）。
3. `fetch --wait` → `qa` → 不合格的换种子重生（`submit <id> --seed N`），一次只改一个变量 → `post` 产出 `assets/bgm/*.ogg`。
4. 按 §4 接入游戏；`$G --headless --path . --import`；跑 compile_check / smoke_ui / autoplay_check。
5. 每个阶段 git 提交；派多个 pi 子 agent 分别审查（代码、数据/文档一致性、曲目与场景是否匹配）→ 修正 → 打包。
6. 「打包」的含义待与用户确认：导出 Windows 可执行包（本机未安装 Godot 4.7.2 导出模板，需下载或在 export_presets 里指定自定义模板路径）还是只打包音乐/项目。
