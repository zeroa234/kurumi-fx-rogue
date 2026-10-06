# 版本历史

按时间倒序。提交哈希对应仓库 `D:/agent` 的 git 历史（`git log -- projects/kurumi-fx-rogue`）。

## 2026-10-07

### Android 打包与触屏适配
- 新增 `export_presets.cfg`（Android：arm64-v8a + armeabi-v7a，横屏，debug 签名）；`project.godot` 开启 `textures/vram_compression/import_etc2_astc`（Android 导出的硬性要求）。
  产物 `output/kurumi-fx-rogue.apk`（59MB，不入库）；构建命令与依赖见 README「打包 Android」、`docs/maintenance.md` §7。
- 触屏适配（键盘快捷键全部保留）：交易界面顶栏新增「菜单」按钮（等价 Esc——手机原本没有打开暂停菜单的入口，肉鸽交易中无法退出）；
  图表单指拖动空白处平移（手机没有右键）、双指捧合缩放（`ChartView`）；对话框按住不放快进（等价 Ctrl）。
- 手机显示与存档安全：`Game._setup_mobile_display()` 在手机上把整数缩放改为小数缩放（桌面不变，仍整数缩放）；
  退出/返回键时落盘（`NOTIFICATION_WM_CLOSE_REQUEST` / `NOTIFICATION_WM_GO_BACK_REQUEST`）。
- 回归：compile_check `0 failures`、smoke_ui `SMOKE DONE`、tutorial_driver 各章步骤满、autoplay_check `0 stalled`。

## 2026-10-06

### 背景音乐（进行中）
- YuE2 纯器乐 BGM 计划：24 首曲目清单 `config/bgm-cues.json`、生成管线 `scripts/gen_bgm.py`、QA `scripts/bgm_qa.py`、播放器 `src/ui/bgm.gd`（未接入）。进度见 `docs/bgm.md` §5。

### 文档
- 新增维护手册 `docs/maintenance.md`、数据字段参考 `docs/data-reference.md`、本变更记录；重写 `docs/story-format.md`；GDD 与实现同步并列出未实现项；README 加文档索引与全部测试。

### 修复
- `fa39a0e` **剧情自动播放段卡死**：第 1 章回放在 2008/10/01 09:15 停住无法继续（第 4 章开头、第 11、12 章同样隐患）。
  原因：速度被剧本锁定时，重大新闻/指标/维持率告警/强平的自动暂停把速度设为 0，玩家无法恢复。
  修复：锁定速度时不自动暂停；对话框/说明框/暴走冲动关闭后恢复原速度；Esc「继续」恢复原速度。新增 `tests/autoplay_check.tscn`。
- `68d8c5d` 教程最后的 `finish` 步骤未计入完成导致判负；第 4 章开局维持率过低可能被直接强平（加 `stopout_delta` 缓冲）；第 9 章达不成目标时剧情不推进（`any` 条件加时限）。
- `077b654` 报价停止期间禁止成交/强平，延后到恢复报价；同时第 11 章预置仓位由 330 枚调到 230 枚。实测不足金约 1.22 億，与原作「1億円以上（一说逾1.2億）」一致（修复前只有 8355 万，因为强平在暴跌第一根 K 线就成交了）。
- `a9865ba` 图鉴类型推断编译错误。

### 美术与音效
- `a5d9e49` 86 项像素素材：久留美 11 种表情（LoRA）、仲间 9 张（官方人设 IC 参考）、父母剪影、19 背景、3 CG、40 图标、Q 版；cg_win 改为平视构图；白色物体改绿底抠图。
- `dd0ade7` Blender 渲染的旋转 ¥ 金币序列帧（FP 显示）。
- `8cc9aa9` 8-bit 合成音效。

### 功能
- `d71a217` 久留美对灾害/央行/谣言/辟谣/闪崩/钉住撤销/干预/指标惊喜/芽吹喊单的专属反应。
- `93b8684` 图鉴；图表显示下一指标倒计时。
- `b79f6d6` 交易界面每帧最多刷新一次；存档往返测试。
- `077b654` 剧情第 7~15 章（原作第 11~53 話）。
- `3ce3dfe` 肉鸽模式：地图、交易/精英/Boss 节点、事件、商店、休息、手法/道具/诅咒、仲间主被动、借金、局外养成、挑战度、经典战役入口、平衡模拟。
- `888daa1` 标题/章节选择/设置、剧情播放器与教学导演、新手教程第 1~6 章。
- `781abaa` 像素交易主界面。
- `7dcbc31` 项目骨架、GDD、原作调研、多因子行情/交易/事件核心引擎。
