class_name DialogueBox
extends Control
## 视觉小说式对话框。lines = [{who, face, text, side?, bg?, cg?, sfx?, shake?}]
## 点击 / 空格 / 回车 前进；打字机效果；Ctrl 快进（手机：按住不放）；Esc 跳过全部（skippable 时）。

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
var _hold := false # 触屏按住不放 = 快进

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
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
	_next()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_Z]:
			_advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and skippable:
			_end()
			get_viewport().set_input_as_handled()

func _input(event: InputEvent) -> void:
	# 手机没有 Ctrl：按住不放等价于长按 Ctrl 快进
	if event is InputEventScreenTouch:
		_hold = event.pressed
	elif event is InputEventScreenDrag:
		_hold = true

func _process(delta: float) -> void:
	var fast := _hold or Input.is_key_pressed(KEY_CTRL)
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

func _end() -> void:
	set_process(false)
	finished.emit()
	queue_free()
