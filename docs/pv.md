# 宣传 PV

成片：`output/pv/kurumi-fx-rogue-pv.mp4`（1920×1080 / 30fps / H.264 CRF16 + AAC 256k，71.5 秒，约 40 MB，不入库）。响度 −16.0 LUFS、峰值 −2.2 dBFS（配乐 +3.5 dB，限幅 −2.5 dB）。
全部可复现：实机画面由 Godot Movie Maker 录制，合成由脚本按剪辑表逐帧渲染。

## 1. 结构（与配乐对齐）
配乐从原曲 41 秒处开始播，所以 **PV 时间 = 原曲时间 − 41**。

| PV 秒 | 段落 | 内容 | 配乐 |
|---|---|---|---|
| 0–22 | 序章 | 2008 年秋 → 母亲的澳元/日元暴跌（第1章实机回放）→ 四个月后 → 雨夜的久留美 →「把 2000万円 取回来！」 | 安静段，58.8~60.4 换气 |
| 22–26 | Logo | 主视觉 + 标题，闪白 + 震屏 | 原曲 63.0 秒爆发 |
| 26–42 | 玩法 | 交易（止盈、CPI 速报）· 剧情对话 · 仲间 · 肉鸽地图 · 道具图标 · 局外养成，每镜一个小节 | 高能段，小节约 2.49 秒 |
| 42–57 | 高潮 | 2015.01.15 18:30 → 第11章瑞郎冲击实机（平静 → 插播速报 → 暴跌 → 强制平仓 不足金 1.22 亿円）→ cg_shock | 断奏段（原曲 83.2 起） |
| 57–66 | 反转 | 「这一次——」「轮到你来交易。」→ 30 万円 → 2000 万円计数 | 原曲 103 秒再推起 |
| 66–71.5 | 片尾 | 标题、模式、免责与素材声明 | 原曲 108 秒结束，提前淡出 |

文案只用第1章已有的剧情事实（见 `data/story/chapters/ch01.json`，出处在 `docs/research/manga-reference.md`），其余是玩法介绍；片尾注明非官方同人、示意走势、AI 生成素材。

## 2. 文件
| 路径 | 内容 |
|---|---|
| `config/pv-edit.json` | 剪辑表：镜头顺序、时长、素材、字幕、特效、音效时间点、配乐偏移（字段说明在 `_doc`） |
| `scripts/pv/pv_capture.gd` + `.tscn` | 录制驱动：`-- --clip=<名字>` 打开对应场景，替玩家关弹窗、调速度、下单、翻对话 |
| `scripts/pv/capture_all.sh` | 逐个片段跑 Movie Maker → `output/pv/raw/<片段>/f########.png`（640×360），录前备份存档、结束还原 |
| `scripts/pv/make_pv.py` | 合成器（Pillow 逐帧 → ffmpeg） |
| `scripts/pv/music_probe.py` | 配乐旁证：demucs 人声声部送 whisper-small 识别 + 每秒能量 + 节拍 |
| `scripts/pv/strip_vocals.py` | demucs 去人声（drums+bass+other） |
| `assets/pv/` | 关键帧 `pv_resolve / pv_key / pv_rain.png`、配乐 `pv_theme.ogg`；来源（提示词、种子、作业号、后期）在 `index.json`。有 `.gdignore`，不会被导入或打进游戏包 |
| `output/hires/` | 游戏美术的高清原图（`gen_assets.py` 产出，不入库）；PV 用到 `bg_living_dim`、`cg_shock`、`cg_win` |

## 3. 重新出片
```bash
cd projects/kurumi-fx-rogue
bash scripts/pv/capture_all.sh                 # 录全部实机片段（约 1 分钟；会弹出游戏窗口）
python scripts/pv/make_pv.py --stills 6,24,50  # 看几个时刻的单帧 → output/pv/stills/
python scripts/pv/make_pv.py --preview         # 960×540 快速预览 → output/pv/preview.mp4
python scripts/pv/make_pv.py                   # 成片（约几分钟）
```
- 只改字幕/时长/特效：改 `config/pv-edit.json` 后直接重新合成，不必重录。
- 改了游戏界面：重录对应片段（`capture_all.sh trade snb`），再检查剪辑表里的 `from` 帧号是否还对得上（行情是固定种子，界面不变时帧号稳定）。
- 片段名与录制秒数在 `capture_all.sh` 的 `ALL=`；驱动里还保留了 `hub`、`codex`（本机存档进度低，画面多为锁定/有进行中的局，没有用）。

## 4. 实机片段（录制驱动做了什么）
| 片段 | 场景 | 驱动动作 | 剪辑用到的帧 |
|---|---|---|---|
| `title` | 标题 | 无 | 未用 |
| `lehman` | 第1章场景2（母亲的交易，2008年10月示意走势） | 关开场对话，1 小时图，速度 4 | 30 起 ×4 倍速 |
| `trade` | 沙盒同款配置（全部情报能力） | 「影子会话」先看后 N 个 tick 的走向再替玩家选方向下单、设止损止盈：做空美元/日元止盈 → 看日历 → 做多英镑/日元撞上 CPI 速报 | 228 起、420 起 |
| `dialogue` | 第8章场景1（四人比赛） | 每 2.4 秒翻一句 | 284 起（久留美那句） |
| `snb` | 第11章场景2 | 快进到第 3 交易日 16:00，15 分图慢速播放；弹窗停留 1.5 秒后替玩家点掉 | 200 平静、300 插播、374 暴跌、389 强制平仓 |
| `map` | 肉鸽地图（种子 777） | 无 | 40 起 |
| `meta` | 局外养成 | 无 | 60 起 |
| `chapters` | 章节选择 | 只在内存里把全部章节标为已读（同 Shift+F9，但不写盘） | 未用 |

「影子会话」：行情是固定种子的确定性模拟，驱动用同配置另开一个 `TradeSession` 往后跑，选顺方向、止盈设为顺向最大浮盈的 80%。画面上的一切仍是游戏真实逻辑，只是替玩家选了「对」的方向。

## 5. 素材来源与已知问题
- **关键帧**：ComfyUI `anima-t2i` + `kurumi.safetensors`（与游戏立绘同一 LoRA），各重画过一次（见 `index.json` 的 `note`）。
- **配乐**：YuE2 本地生成。`instrumental:true` 只是文字引导，三个候选都唱了歌（whisper 在人声声部里识别出成句歌词），所以用 demucs 去掉了人声声部；复检人声声部 −55 ~ −72 dB、识别结果为乱码。**没有经过人耳试听**——去人声可能留下轻微的「挖空」感，正式发布前请听一遍；不满意可换 `output/pv/music/c2_inst.wav` / `c3_inst.wav` 或重新生成，改 `music.offset` 让爆发点对上 PV 22 秒。
- 原曲在 token 上限处截断、没有自然收尾，片尾 64.5~67 秒淡出，最后 4.5 秒只有片尾音效。
- **音效**：游戏自己的 `assets/sfx/*.wav`。**字体**：Fusion Pixel（OFL），12px 渲染后整数倍放大。
- 游戏美术高清原图在 `output/hires/`（不入库）；换机器重出片需要先跑 `python scripts/gen_assets.py` 生成，或改剪辑表换掉 `hires:` 素材。
