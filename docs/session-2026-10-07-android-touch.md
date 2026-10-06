# 会话记录 2026-10-07 · Android 打包与触屏适配

> 一次性记录：这一轮「打 APK 给手机试玩」做了什么、怎么复现、真机还要验什么。
> 长效约定（触屏输入规则、依赖位置、已知取舍）已经并进 `docs/maintenance.md`，这里只记过程。

## 1. 起因与结论

需求：把项目打成 APK 在手机上试玩；先不推进游戏内容。检查后发现两件事必须一起解决，否则手机上是「能装但玩不了」：

1. 本机没有导出模板 / Android SDK / JDK，Android 导出完全没配置（`export_presets.cfg` 不存在，编辑器设置里的 SDK 路径指向不存在的目录）。
2. 游戏是纯键鼠操作：**交易界面没有任何入口能打开暂停菜单**（`Esc` 专属），手机上无法中途退出肉鸽交易节点；图表缩放只认滚轮、平移只认右键。

结论：配好工具链 + 补最小触屏适配，产出 `output/kurumi-fx-rogue.apk`（59.4 MB，debug 签名）。

## 2. 环境（新装的，都在 D:）

| 依赖 | 版本 | 位置 | 谁在用 |
|---|---|---|---|
| Godot 导出模板 | 4.7.2.stable | `%APPDATA%/Godot/export_templates/4.7.2.stable/`（`android_debug.apk` / `android_release.apk` / `android_source.zip`） | 导出必装；必须在 Godot 用户配置目录 |
| Eclipse Temurin JDK | 17.0.13+11 | `D:/tools/jdk17/jdk-17.0.13+11` | `apksigner`、gradle |
| Android SDK | build-tools 35.0.0 / platform-tools / platforms;android-35 | `D:/tools/android-sdk` | 对齐、签名、`adb` |
| 调试签名 | 自建 | `%APPDATA%/Godot/keystores/debug.keystore`（口令均 `android`） | debug APK 签名 |

编辑器设置改动：`export/android/java_sdk_path`、`export/android/android_sdk_path`（`%APPDATA%/Godot/editor_settings-4.7.tres`）。
模板 1.28 GB 与 SDK 从 GitHub / `dl.google.com` 下载时走了本机代理 `http://127.0.0.1:7897`（直连 GitHub 卡在 6 MB）。

## 3. 打包命令（可复现）

```bash
G=D:/godot/Godot_v4.7.2-stable_win64_console.exe
JAVA_HOME=D:/tools/jdk17/jdk-17.0.13+11   # apksigner 需要 JDK17
cd projects/kurumi-fx-rogue
$G --headless --path . --export-debug "Android" output/kurumi-fx-rogue.apk
D:/tools/android-sdk/platform-tools/adb.exe install -r output/kurumi-fx-rogue.apk   # 可选：USB 直装
```

坑：`project.godot` 必须开 `rendering/textures/vram_compression/import_etc2_astc=true`，否则报「需要 ETC2/ASTC 纹理压缩格式」直接拒绝导出。
预设用 `gradle_build/use_gradle_build=false`（走预编译模板 + zipalign + apksigner，不需要 Gradle 依赖下载）。

## 4. 代码改动（键盘快捷键一个没删）

| 文件 | 位置 | 改动 |
|---|---|---|
| `src/ui/trade_screen.gd` | `_menu_btn` 151~157 | 顶栏右上加「菜单」按钮 → 复用现有 `_pause_menu()`（＝Esc）：继续 / 新闻自动暂停设置 / 返回标题（保存退出） |
| `src/ui/chart_view.gd` | `_gui_input` 59、`_set_candle_w` 103、`_touch_pressed` 112、`_touch_moved` 126、`_begin_pinch` 152 | 单指拖空白处＝平移（手机没有右键）；双指捏合＝缩放、双指整体移动＝平移；手势期间用 `_multitouch` 屏蔽触摸模拟出的鼠标事件（否则会边缩放边拖 SL/TP 单）；新增 `InputEventMagnifyGesture` 分支 |
| `src/ui/dialogue_box.gd` | `_input` 87、`_process` | 触摸按住不放＝快进（等价长按 Ctrl） |
| `src/core/game.gd` | `_setup_mobile_display` 51、`_notification` 59 | 手机上把整数缩放改为小数缩放（原整数缩放下 1080p 手机只用中间 640×360 一小块，桌面不变）；`WM_CLOSE_REQUEST` / `GO_BACK_REQUEST` 时先 `Save.write()` |

行为变化提示（桌面端也能感知）：图表**左键拖空白处现在会平移**（以前什么都不做）；关窗口/返回键会先落盘再退出。

## 5. 文档改动

- `README.md`：新增「打包 Android（手机试玩）」；「操作」补手机操作说明。
- `docs/maintenance.md`：§3 加第 15 条「触屏输入」约定；§6 更新「导出」并把触屏细节/手机显示/平台差异列成已知取舍；§7 补 JDK、SDK、模板、调试签名四项依赖。
- `docs/GDD.md` §7 补一行触屏操作；`docs/CHANGELOG.md` 加 2026-10-07 条目。

## 6. 验证

| 项 | 结果 |
|---|---|
| `compile_check` | 0 failures |
| `smoke_ui` | SMOKE DONE |
| `tutorial_driver` | 各章「步骤 n/n」全满 |
| `autoplay_check` | 0 stalled |
| 顶栏排版 | 截图 `agent/temp/kurumi-apk/trade_top.png` 确认「菜单」没挤掉目标/剩余天数 |
| APK 签名 | `apksigner verify --print-certs` 通过（CN=Android Debug） |

## 7. 真机还要验（写这段时未验证）

1. 单指拖空白处平移（走触摸模拟鼠标，预期稳）；**双指捏合缩放**（依赖 `InputEventScreenTouch/Drag` 到达 `Control._gui_input`，若无效需改成 `_input` + 区域判定）。
2. 「菜单」→ 继续 / 返回标题；肉鸽交易中退出是否正常保存。
3. 安卓返回键：Godot 默认直接退 APP（已先落盘）。想改成「返回键＝打开暂停菜单」需 `quit_on_go_back=false` + 拦截。
4. 非 16:9 屏幕上下留黑边（保 `CONTENT_SCALE_ASPECT_KEEP` 不裁切）；要铺满得先把 640×360 绝对坐标布局改成自适应。
5. 列表滚动靠 Godot `ScrollContainer` 内建触摸拖动（未真机确认）。

## 8. git 与回滚

| hash | 内容 |
|---|---|
| `13354d4` | build：Android 导出预设 + `import_etc2_astc` |
| `aeb5aae` | chore：补 `bgm.gd.uid` |
| `0089f59` | feat：触屏适配 + 手机显示与退出落盘 |

- 只想留打包、不要触屏改动：`git revert 0089f59`。
- 不再打手机包：可删 `export_presets.cfg`、`D:/tools/android-sdk`（425 MB）、`D:/tools/jdk17`（305 MB）、`%APPDATA%/Godot/export_templates/4.7.2.stable`（426 MB）。
  注意 `project.godot` 的 `import_etc2_astc` 不要单独回退，否则 Android 导出会重新报错（它只影响导入格式，留着无害）。
- `output/` 不入库，APK 只在本机。
