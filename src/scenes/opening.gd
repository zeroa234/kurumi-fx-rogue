extends Control
class_name Opening
## 开场 PV：assets/video/opening.ogv（scripts/pv/make_pv.py --game 生成，640×360 与视口一致）。
## 首次启动由 boot 自动播放；设置里可以重看，或改成每次启动都播。
## 跳过：任意键 / 点击 / 轻点 / 返回键 先出现「再按一次跳过」，提示期间再按一次才跳过（防误触）。
## Game.params：next = 播完去的场景（默认标题）；gate = 先等一次点击再播
## （网页版自动播放时用：浏览器在用户操作前不让出声，这一下不算跳过）。

const VIDEO := "res://assets/video/opening.ogv"
const SCENE := "res://src/scenes/opening.tscn"
const TITLE := "res://src/scenes/title.tscn"
const SKIP_WINDOW := 2.5

var _next := TITLE
var _player: VideoStreamPlayer
var _hint: PanelContainer
var _gate: Control
var _fade: ColorRect
var _armed_t := 0.0 # >0：「再按一次跳过」显示中
var _leaving := false

static func available() -> bool:
	return ResourceLoader.exists(VIDEO)

## boot 用：没看过开场，或设置了每次启动都播
static func should_autoplay() -> bool:
	return available() and (not bool(Save.data.story.get("opening_seen", false)) \
		or bool(Save.setting("opening_every_launch", false)))

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_next = Game.params.get("next", TITLE)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	if not available():
		_leave()
		return
	_player = VideoStreamPlayer.new()
	_player.stream = load(VIDEO)
	_player.expand = true
	_player.set_anchors_preset(Control.PRESET_FULL_RECT)
	_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_player.volume = float(Save.setting("bgm", 0.6))
	_player.finished.connect(_leave)
	add_child(_player)
	_build_hint()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	if Game.params.get("gate", false):
		_build_gate()
	else:
		_player.play()

func _build_hint() -> void:
	_hint = PanelContainer.new()
	_hint.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.1, 0.85), UI.BORDER_HI, 1, 3))
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(UI.label(("再点一下" if Game.touch else "再按一次") + "跳过 ▶▶", UI.TEXT))
	_hint.visible = false
	add_child(_hint)
	_hint.reset_size()
	_hint.position = Vector2(640 - _hint.size.x - 8, 360 - _hint.size.y - 8)

func _build_gate() -> void:
	_gate = Control.new()
	_gate.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := UI.label("点击开始", UI.PINK, 24)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gate.add_child(l)
	add_child(_gate)
	var tw := l.create_tween().set_loops()
	tw.tween_property(l, "modulate:a", 0.3, 0.8)
	tw.tween_property(l, "modulate:a", 1.0, 0.8)

func _input(event: InputEvent) -> void:
	if _leaving:
		return
	if event is InputEventKey:
		if not event.pressed or event.echo:
			return
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			return # 交给 Game 切全屏
	elif event is InputEventMouseButton:
		# 触屏的轻点会同时来 ScreenTouch 和模拟鼠标，只认后者，不然点一下算两次；滚轮不算
		if not event.pressed or event.button_index > MOUSE_BUTTON_MIDDLE:
			return
	elif event is InputEventJoypadButton:
		if not event.pressed:
			return
	else:
		return
	get_viewport().set_input_as_handled()
	_press()

## 安卓返回键（Game.back 先问场景）
func _on_back() -> bool:
	if not _leaving:
		_press()
	return true

func _press() -> void:
	if _gate != null:
		_gate.queue_free()
		_gate = null
		_player.play()
	elif _armed_t > 0.0:
		_leave()
	else:
		_armed_t = SKIP_WINDOW
		_hint.visible = true

func _process(delta: float) -> void:
	if _armed_t > 0.0:
		_armed_t -= delta
		if _armed_t <= 0.0:
			_hint.visible = false

func _leave() -> void:
	if _leaving:
		return
	_leaving = true
	Save.data.story.opening_seen = true
	Save.write()
	if _player == null:
		Game.goto(_next)
		return
	_hint.visible = false
	var tw := create_tween().set_parallel()
	tw.tween_property(_fade, "color:a", 1.0, 0.35)
	tw.tween_property(_player, "volume", 0.0, 0.35)
	tw.chain().tween_callback(func(): Game.goto(_next))
