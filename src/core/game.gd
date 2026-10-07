extends Node
## 全局：场景切换与跨场景参数；手机适配（返回键＝Esc、长按看按钮说明、全局提示条）。

var params := {}
var run: RunState = null # 当前肉鸽局（RunState）
## 触屏设备：按平台显示操作提示。桌面调试可加 `-- --touch` 模拟
var touch := false

## 返回键 / Esc 在这些界面＝回标题（与界面上的「← 返回」一致）
const BACK_TO_TITLE := [
	"res://src/scenes/chapter_select.tscn", "res://src/scenes/battles.tscn", "res://src/scenes/codex.tscn",
	"res://src/scenes/settings.tscn", "res://src/run/meta_screen.tscn", "res://src/run/run_hub.tscn",
]
const TITLE_SCENE := "res://src/scenes/title.tscn"
const LONG_PRESS := 0.5 # 秒
const LONG_PRESS_MOVE := 6.0 # 视口像素（640x360 空间）

var _overlay: CanvasLayer
var _tip: PanelContainer
var _tip_lbl: Label
var _tip_t := 0.0
var _lp_t := -1.0 # 单指按住计时；-1 = 不在计时
var _lp_pos := Vector2.ZERO
var _lp_fired := false
var _quit_armed_ms := -100000

func _ready() -> void:
	touch = OS.has_feature("mobile") or "--touch" in OS.get_cmdline_user_args()
	_setup_mobile_display()
	_build_overlay()
	# 调试：-- --shot=res路径/或绝对路径 --shot-delay=秒 [--scene=res://...] 截图后退出
	var args := OS.get_cmdline_user_args()
	var shot := ""
	var delay := 3.0
	for a in args:
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a.begins_with("--shot-delay="):
			delay = float(a.substr(13))
		elif a.begins_with("--scene="):
			goto(a.substr(8), params)
		elif a.begins_with("--chapter="):
			params["chapter"] = a.substr(10)
		elif a.begins_with("--scene-index="):
			params["scene_index"] = int(a.substr(14))
		elif a == "--newrun":
			# 调试：用当前存档开一局（不写盘）
			run = RunState.create({"broker": "overseas", "friends": ["mochiko", "mebuki"], "seed": 777})
		elif a.begins_with("--node="):
			params["node"] = a.substr(7)
	if shot != "":
		_take_shot(shot, delay)

func _take_shot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SHOT ", path)
	get_tree().quit()

func goto(scene: String, p := {}) -> void:
	params = p
	get_tree().call_deferred("change_scene_to_file", scene)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			var fs := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if fs else DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif event.keycode == KEY_ESCAPE:
			# 场景里没人处理的 Esc（交易画面、对话框会先处理自己的）
			back(false)

## 返回：安卓返回键与没被处理的 Esc 都走这里。
## 场景实现 `_on_back() -> bool`（返回 true＝已处理）时优先交给场景：剧情/交易里是开关暂停菜单。
func back(from_back_key: bool) -> void:
	var s := get_tree().current_scene
	if s == null:
		return
	if s.has_method("_on_back") and s._on_back():
		return
	if s.scene_file_path in BACK_TO_TITLE:
		Save.write()
		goto(TITLE_SCENE)
	elif s.scene_file_path == TITLE_SCENE:
		if not from_back_key:
			return # 桌面 Esc 不退出游戏
		if Time.get_ticks_msec() - _quit_armed_ms < 2000:
			Save.write()
			get_tree().quit()
		else:
			_quit_armed_ms = Time.get_ticks_msec()
			toast("再按一次返回键退出")
	elif from_back_key:
		toast("请使用画面上的按钮")

## 手机：640x360 视口 + 整数缩放会让 1080p 屏幕只用中间一小块，改成小数缩放铺满宽度（保留黑边不裁切）。
func _setup_mobile_display() -> void:
	if not OS.has_feature("mobile"):
		return
	var w := get_window()
	w.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP

## 关窗口 / 切到后台（手机可能随后被系统回收）时落盘；返回键不再直接退出（project.godot quit_on_go_back=false）。
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_CLOSE_REQUEST:
			Save.write()
			get_tree().quit()
		NOTIFICATION_APPLICATION_PAUSED:
			Save.write()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			back(true)

# ---------------------------------------------------------------- 全局浮层：提示条 / 长按说明

func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = 100
	add_child(_overlay)
	_tip = PanelContainer.new()
	_tip.add_theme_stylebox_override("panel", UI.box(Color("120c1e"), UI.BORDER_HI, 1, 3))
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.visible = false
	_tip_lbl = UI.label("")
	_tip.add_child(_tip_lbl)
	_overlay.add_child(_tip)

## 屏幕下方的短提示（不挡操作）
func toast(text: String, secs := 2.0) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.1, 0.92), UI.YELLOW, 1, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(UI.label(text, UI.YELLOW))
	_overlay.add_child(p)
	p.reset_size()
	p.position = Vector2(floorf((640 - p.size.x) / 2.0), 300)
	var tw := p.create_tween()
	tw.tween_interval(secs)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

## 长按看说明：手机没有鼠标悬停，tooltip_text 原本完全看不到。
## 单指按住 LONG_PRESS 秒不动 → 显示手指下控件的 tooltip_text；之后松手不触发按钮（避免长按“买”时顺手下单）。
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.index != 0:
			_lp_t = -1.0 # 多指手势（图表捏合）不算长按
		elif event.pressed:
			_lp_t = 0.0
			_lp_pos = event.position
			_lp_fired = false
			_tip.visible = false
		else:
			_lp_t = -1.0
			if _lp_fired:
				_tip_t = 2.0 # 松手后再显示一会儿
	elif event is InputEventScreenDrag:
		if event.index == 0 and _lp_t >= 0.0 and event.position.distance_to(_lp_pos) > LONG_PRESS_MOVE:
			_lp_t = -1.0
	elif _lp_fired and event is InputEventMouse and event.device == InputEvent.DEVICE_ID_EMULATION:
		# 长按触发后，把触摸模拟出来的鼠标事件移到屏幕外：按钮会认为手指已经移出，松手时不再 pressed
		event.position = Vector2(-4096, -4096)
		event.global_position = event.position

func _process(delta: float) -> void:
	if _lp_t >= 0.0:
		_lp_t += delta
		if _lp_t >= LONG_PRESS:
			_lp_t = -1.0
			_long_press(_lp_pos)
	if _tip_t > 0.0:
		_tip_t -= delta
		if _tip_t <= 0.0:
			_tip.visible = false

func _long_press(pos: Vector2) -> void:
	var hit: Array = [null]
	_pick(get_tree().root, pos, Rect2(Vector2.ZERO, Vector2(640, 360)), hit)
	var text := ""
	var c: Control = hit[0]
	while c != null:
		if c.tooltip_text != "":
			text = c.tooltip_text
			break
		var par := c.get_parent()
		c = par as Control
		if c != null and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.tooltip_text == "":
			break # 不越过另一个会吃掉点击的控件
	if text == "":
		return
	_lp_fired = true
	# 立刻让被按住的按钮“松开”（视觉复位，且松手不触发）
	var mm := InputEventMouseMotion.new()
	mm.device = InputEvent.DEVICE_ID_EMULATION
	mm.button_mask = MOUSE_BUTTON_MASK_LEFT
	mm.position = Vector2(-4096, -4096)
	mm.global_position = mm.position
	Input.parse_input_event(mm)
	# 先不换行量宽度，太宽再固定宽度自动换行（autowrap 的 Label 最小宽度是 0，不能直接用）
	_tip_lbl.text = text
	_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	_tip_lbl.custom_minimum_size.x = 0
	_tip.reset_size()
	if _tip.size.x > 260:
		_tip_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		_tip_lbl.custom_minimum_size.x = 252
		_tip.reset_size()
	var p := pos - Vector2(_tip.size.x / 2.0, _tip.size.y + 12)
	if p.y < 2:
		p.y = pos.y + 16
	_tip.position = Vector2(clampf(p.x, 2, 638 - _tip.size.x), clampf(p.y, 2, 358 - _tip.size.y)).floor()
	_tip.visible = true
	_tip_t = 0.0

## 找手指下最上层的可点控件（树的先序遍历中最后一个命中的；考虑 clip_contents 与可见性）
func _pick(n: Node, pos: Vector2, clip: Rect2, hit: Array) -> void:
	if n == _overlay:
		return
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control:
		var c := n as Control
		var r := c.get_global_rect()
		if c.mouse_filter != Control.MOUSE_FILTER_IGNORE and clip.has_point(pos) and r.has_point(pos):
			hit[0] = c
		if c.clip_contents:
			clip = clip.intersection(r)
	for ch in n.get_children():
		_pick(ch, pos, clip, hit)
