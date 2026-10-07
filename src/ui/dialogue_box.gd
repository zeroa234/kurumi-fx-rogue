class_name DialogueBox
extends Control
## 视觉小说式对话框。lines = [{who, face, text, side?, bg?, cg?, sfx?, shake?}]
## 点击 / 空格 / 回车 前进；打字机效果；Ctrl 或按住不放（≥HOLD_DELAY 秒）快进；Esc 跳过全部（skippable 时）。
## 右上角有「快进」（开关，点对话框取消）与「跳过」按钮，以及按平台显示的操作提示——手机没有 Ctrl/Esc。

signal finished
signal line_shown(index: int, line: Dictionary)
signal bg_changed(bg: String)

var lines: Array = []
var skippable := true
var dim_background := true
var _i := -1
var _shown := 0.0
var _full := ""
var _name_lbl: Label
var _text_lbl: RichTextLabel
var _left: TextureRect
var _right: TextureRect
var _box: PanelContainer
var _arrow: Label
var _name_panel: PanelContainer
var _blink := 0.0
## 按住超过这么久才算「长按快进」；轻点只前进一句（之前一按下就快进，手机上轻点会连跳好几句）
const HOLD_DELAY := 0.45
var _press_t := -1.0 # 在对话框上按住的秒数；-1 = 没按
var _skip_mode := false # 「快进」开关
var _done := false
var _fast_lbl: Label
var _skip_btn: Button
## 上一个对话框结束时还在长按快进（记录结束时刻）：紧接着的下一段对话不用重新按
static var _carry_fast_ms := -100000

func _ready() -> void:
	# 代码创建的控件进树后才设锚点：必须连同偏移一起设，否则保持 0×0（点不到、弹窗遮罩也不显示）
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if dim_background:
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.35)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
	_left = TextureRect.new()
	_left.position = Vector2(24, 360 - 96 - 256)
	_left.size = Vector2(256, 256)
	_left.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_left.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_left)
	_right = TextureRect.new()
	_right.position = Vector2(640 - 24 - 256, 360 - 96 - 256)
	_right.size = Vector2(256, 256)
	_right.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_right.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right.flip_h = true
	_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_right)
	_box = PanelContainer.new()
	_box.add_theme_stylebox_override("panel", UI.box(Color(0.08, 0.05, 0.14, 0.94), UI.PINK, 1, 8))
	_box.position = Vector2(16, 360 - 92)
	_box.size = Vector2(608, 84)
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)
	_text_lbl = RichTextLabel.new()
	_text_lbl.bbcode_enabled = true
	_text_lbl.scroll_active = false
	_text_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_box.add_child(_text_lbl)
	_name_panel = PanelContainer.new()
	_name_panel.position = Vector2(24, 360 - 106)
	_name_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_panel)
	_name_lbl = UI.label("", UI.WHITE)
	_name_panel.add_child(_name_lbl)
	_arrow = UI.label("▼", UI.PINK)
	_arrow.position = Vector2(604, 360 - 20)
	add_child(_arrow)
	_build_controls()
	if Time.get_ticks_msec() - _carry_fast_ms < 3000 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_press_t = HOLD_DELAY
	_carry_fast_ms = -100000
	_next()

## 对话框右上方：操作提示 + 快进 / 跳过
func _build_controls() -> void:
	var h := UI.hbox(3)
	h.alignment = BoxContainer.ALIGNMENT_END
	h.position = Vector2(16, 360 - 106)
	h.size = Vector2(608, 13)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(h)
	_fast_lbl = UI.label("▶▶", UI.YELLOW)
	_fast_lbl.visible = false
	h.add_child(_fast_lbl)
	var tip := "轻点 继续 · 长按 快进" if Game.touch else "点击/空格 继续 · 按住 Ctrl 快进" + (" · Esc 跳过" if skippable else "")
	var tl := UI.label(tip, UI.MUTED)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(tl)
	h.add_child(_bar_btn("快进", func(): _skip_mode = not _skip_mode))
	if skippable:
		_skip_btn = _bar_btn("跳过", _end)
		h.add_child(_skip_btn)

func _bar_btn(t: String, cb: Callable) -> Button:
	var b := UI.button(t, cb)
	b.custom_minimum_size = Vector2(30, 13)
	b.add_theme_stylebox_override("normal", UI.box(Color(0.08, 0.05, 0.14, 0.9), UI.BORDER, 1, 0))
	b.add_theme_stylebox_override("hover", UI.box(Color("3d3060"), UI.BORDER_HI, 1, 0))
	b.add_theme_stylebox_override("pressed", UI.box(Color("4a3a75"), UI.PINK, 1, 0))
	return b

func _gui_input(event: InputEvent) -> void:
	# 手机上单指触摸会被模拟成左键，所以这里同时处理鼠标与触屏
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _skip_mode:
				_skip_mode = false # 快进中点一下 = 停止快进
			else:
				_advance()
			_press_t = 0.0
		else:
			_press_t = -1.0
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z]:
			_advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and skippable:
			_end()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _press_t >= 0.0:
		# 松手的事件可能落在别处（比如手指滑出窗口），以实际按键状态为准
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_press_t += delta
		else:
			_press_t = -1.0
	var fast := _is_fast()
	_fast_lbl.visible = fast
	var speed := 2000.0 if fast else 50.0
	if _shown < _full.length():
		_shown = minf(_full.length(), _shown + delta * speed)
		_text_lbl.visible_characters = int(_shown)
		_arrow.visible = false
	else:
		_blink += delta
		_arrow.visible = fmod(_blink, 0.8) < 0.5
		if fast:
			_next()

func _advance() -> void:
	if _shown < _full.length():
		_shown = _full.length()
		_text_lbl.visible_characters = -1
		return
	Sfx.play("click")
	_next()

func _next() -> void:
	_i += 1
	if _i >= lines.size():
		_end()
		return
	var l: Dictionary = lines[_i]
	if l.has("bg"):
		bg_changed.emit(l.bg)
	if l.has("sfx"):
		Sfx.play(l.sfx)
	var who: String = l.get("who", "narrator")
	var inf := Portraits.info(who)
	var nm: String = l.get("name", inf.get("name", who))
	_name_lbl.text = nm
	_name_panel.visible = nm != ""
	_name_panel.add_theme_stylebox_override("panel", UI.box(Color(String(inf.get("color", "a89cc8"))).darkened(0.55), Color(String(inf.get("color", "a89cc8"))), 1, 3))
	var face: String = l.get("face", "normal")
	var side: String = l.get("side", "left" if who == "kurumi" else "right")
	var has_portrait: bool = who not in ["narrator", "tv", "note", ""] and not l.get("hide_portrait", false)
	if has_portrait:
		var tex := Portraits.big(who, face)
		if side == "left":
			_left.texture = tex
			_left.modulate = Color.WHITE
			_right.modulate = Color(0.5, 0.5, 0.6)
		else:
			_right.texture = tex
			_right.modulate = Color.WHITE
			_left.modulate = Color(0.5, 0.5, 0.6)
	elif l.get("clear_portraits", false):
		_left.texture = null
		_right.texture = null
	var col := UI.TEXT
	if who == "narrator":
		col = Color("d8cff0")
	elif who == "note":
		col = UI.YELLOW
	_full = String(l.get("text", ""))
	_text_lbl.text = "[color=#%s]%s[/color]" % [col.to_html(false), _full]
	_full = _text_lbl.get_parsed_text()
	_shown = 0.0
	_text_lbl.visible_characters = 0
	line_shown.emit(_i, l)

func _is_fast() -> bool:
	return _skip_mode or _press_t >= HOLD_DELAY or Input.is_key_pressed(KEY_CTRL)

func _end() -> void:
	if _done:
		return # 已经结束（例如「跳过」与最后一句同一帧触发）
	_done = true
	if _press_t >= HOLD_DELAY:
		_carry_fast_ms = Time.get_ticks_msec()
	set_process(false)
	finished.emit()
	queue_free()
