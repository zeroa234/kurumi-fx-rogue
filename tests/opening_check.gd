extends Node
## 开场 PV 的跳过逻辑：按一次只出提示、提示期间再按才跳过、触屏轻点（触摸 + 模拟鼠标）只算一次、
## 网页门槛那一下不算跳过、滚轮不算、提示过期后重新计。会写 opening_seen，结束时还原本机存档文件。

var _backup = null # 原存档文本；null = 原本没有存档
var _ok := true

func _ready() -> void:
	if FileAccess.file_exists(Save.PATH):
		_backup = FileAccess.get_file_as_string(Save.PATH)
	Save.data = Save._default()
	await _run()
	if _backup == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Save.PATH))
	else:
		var f := FileAccess.open(Save.PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	Save.load_save()
	print("OPENING CHECK ", "OK" if _ok else "FAIL")
	get_tree().quit(0 if _ok else 1)

func _run() -> void:
	_check(Opening.available(), "找不到 " + Opening.VIDEO)
	_check(Opening.should_autoplay(), "新存档应自动播放")

	# 1) 键盘：一次出提示，再一次跳过
	var op := await _spawn({})
	_check(op._player.is_playing(), "无门槛时应直接播放")
	await _key(KEY_SPACE)
	_check(op._hint.visible and not op._leaving, "第一次按键只出提示")
	await _key(KEY_SPACE)
	_check(op._leaving, "提示期间第二次按键应跳过")
	_check(Save.data.story.opening_seen, "跳过后记为已看")
	_check(not Opening.should_autoplay(), "看过后不再自动播放")
	Save.data.settings.opening_every_launch = true
	_check(Opening.should_autoplay(), "开了「每次启动都播放」应自动播放")
	op.queue_free()

	# 2) 触屏轻点：Input 会额外模拟一个鼠标事件，必须只算一次
	op = await _spawn({})
	await _tap()
	_check(op._hint.visible and not op._leaving, "一次轻点只出提示（不能被触摸+模拟鼠标算两次）")
	# 滚轮不算
	await _wheel()
	_check(not op._leaving, "滚轮不应跳过")
	# 提示过期后重新计
	op._process(Opening.SKIP_WINDOW + 0.1)
	_check(not op._hint.visible, "提示应过期隐藏")
	await _tap()
	_check(not op._leaving, "过期后的轻点重新只出提示")
	await _tap()
	_check(op._leaving, "第二次轻点应跳过")
	op.queue_free()

	# 3) 网页门槛：第一下只开播
	op = await _spawn({"gate": true})
	_check(not op._player.is_playing() and op._gate != null, "门槛时先不播")
	await _tap()
	_check(op._player.is_playing() and op._gate == null and not op._hint.visible, "门槛点击只开始播放")
	await _tap()
	_check(op._hint.visible and not op._leaving, "开播后的第一下才出提示")
	op.queue_free()

	# 4) 返回键走 _on_back
	op = await _spawn({})
	_check(op._on_back(), "返回键应被开场处理")
	_check(op._on_back() and op._leaving, "两次返回键应跳过")
	op.queue_free()

func _spawn(p: Dictionary) -> Node:
	Game.params = p
	var op: Node = load(Opening.SCENE).instantiate()
	add_child(op)
	await get_tree().process_frame
	return op

func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		Input.parse_input_event(e)
	await _flush()

func _tap() -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.position = Vector2(320, 180)
		e.pressed = pressed
		Input.parse_input_event(e)
	await _flush()

func _wheel() -> void:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_WHEEL_DOWN
	e.pressed = true
	e.position = Vector2(320, 180)
	Input.parse_input_event(e)
	await _flush()

func _flush() -> void:
	Input.flush_buffered_events()
	await get_tree().process_frame
	await get_tree().process_frame

func _check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: ", msg)
		_ok = false
