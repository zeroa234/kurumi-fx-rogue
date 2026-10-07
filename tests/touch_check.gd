extends Node
## 触屏输入自检（需要窗口）：godot --path . res://tests/touch_check.tscn → "TOUCH CHECK: 0 failures"
## 用 Input.parse_input_event 注入 InputEventScreenTouch，走真实的「触摸→模拟鼠标→GUI」链路：
## 1) 对话框：轻点只前进一句（不论按住几帧）、长按快进、「跳过」按钮
## 2) 长按看说明：显示 tooltip_text，且松手不触发按钮；之后的普通轻点仍然有效
## 3) 返回键：剧情段开关菜单；交易段开关暂停菜单
## 不写存档（不走会调用 Save.write 的路径）。
## 加 `-- --shots=<绝对目录>` 时顺便保存对话框 / 剧情菜单 / 交易暂停菜单的截图（检查排版）。

var fails := 0
var shots := ""

func _ready() -> void:
	Game.touch = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.substr(8)
	await _frames(3)
	await _check_dialogue_tap()
	await _check_dialogue_hold()
	await _check_dialogue_skip()
	await _check_long_press()
	await _check_back_story()
	await _check_back_trade()
	print("TOUCH CHECK: %d failures" % fails)
	get_tree().quit()

func _ok(cond: bool, msg: String) -> void:
	print(("  ok   " if cond else "  FAIL ") + msg)
	if not cond:
		fails += 1

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _shot(name_: String) -> void:
	if shots == "":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name_ + ".png"))

func _secs(t: float) -> void:
	await get_tree().create_timer(t).timeout

## 视口坐标（640x360）→ 窗口坐标：parse_input_event 的事件会再经过拉伸变换
func _win(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos

func _touch(pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = _win(pos)
	e.pressed = pressed
	Input.parse_input_event(e)

func _tap(pos: Vector2, hold_frames := 2) -> void:
	_touch(pos, true)
	await _frames(hold_frames)
	_touch(pos, false)
	await _frames(2)

func _dialog(n: int) -> DialogueBox:
	var lines: Array = []
	for i in n:
		lines.append({"who": "narrator", "text": "第%d句：这是一段用来测试触屏输入的对话文字。" % i})
	var d := DialogueBox.new()
	d.lines = lines
	_host().add_child(d) # 和游戏里一样挂在全屏 Control 下（直接挂 Window 下尺寸为 0）
	return d

func _host() -> Control:
	var h := Control.new()
	h.position = Vector2.ZERO
	h.size = Vector2(640, 360)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().root.add_child(h)
	return h

func _check_dialogue_tap() -> void:
	print("[touch] 对话框轻点")
	var d := _dialog(6)
	await _frames(3)
	await _tap(Vector2(320, 200))
	_ok(d._i == 0 and d._shown >= d._full.length(), "第 1 次轻点：补全当前句，不换句（i=%d）" % d._i)
	await _tap(Vector2(320, 200))
	_ok(d._i == 1, "第 2 次轻点：只前进一句（i=%d）" % d._i)
	await _tap(Vector2(320, 200), 12) # 按住约 0.2 秒，仍算轻点
	await _tap(Vector2(320, 200), 12)
	_ok(d._i == 2, "稍慢的轻点（按住 12 帧）也只前进一句（i=%d）" % d._i)
	d.queue_free()
	await _frames(2)

func _check_dialogue_hold() -> void:
	print("[touch] 对话框长按快进")
	var d := _dialog(300)
	await _frames(3)
	_touch(Vector2(320, 200), true)
	await _secs(0.3)
	_ok(d._i <= 1, "按住 0.3 秒还没开始快进（i=%d）" % d._i)
	await _secs(0.7)
	var reached := d._i if is_instance_valid(d) else 999
	_ok(reached >= 5, "按住 1 秒后在快进（i=%d）" % reached)
	_touch(Vector2(320, 200), false)
	await _frames(3)
	if is_instance_valid(d):
		var i0 := d._i
		await _secs(0.3)
		_ok(is_instance_valid(d) and d._i == i0, "松手后停止快进")
		d.queue_free()
	await _frames(2)

func _check_dialogue_skip() -> void:
	print("[touch] 「跳过」按钮")
	var d := _dialog(10)
	var done := [false]
	d.finished.connect(func(): done[0] = true)
	await _frames(3)
	var b: Button = d._skip_btn
	await _tap(b.get_global_rect().get_center())
	_ok(done[0], "点「跳过」结束整段对话")
	await _frames(2)

func _check_long_press() -> void:
	print("[touch] 长按看说明")
	var b := Button.new()
	b.text = "买"
	b.tooltip_text = "测试说明"
	b.position = Vector2(100, 100)
	b.size = Vector2(60, 20)
	var count := [0]
	b.pressed.connect(func(): count[0] += 1)
	get_tree().root.add_child(b)
	await _frames(2)
	var c := b.get_global_rect().get_center()
	_touch(c, true)
	await _secs(0.7)
	_ok(Game._tip.visible and Game._tip_lbl.text == "测试说明", "长按 0.7 秒显示说明")
	_touch(c, false)
	await _frames(3)
	_ok(count[0] == 0, "长按后松手不触发按钮（pressed=%d）" % count[0])
	await _tap(c)
	_ok(count[0] == 1, "之后的普通轻点正常触发（pressed=%d）" % count[0])
	b.queue_free()
	await _frames(2)

func _story(scene_index: int) -> Node:
	Game.params = {"chapter": "ch01", "scene_index": scene_index}
	var sp: Node = load("res://src/story/story_player.tscn").instantiate()
	get_tree().root.add_child(sp)
	get_tree().current_scene = sp
	return sp

func _end_story(sp: Node) -> void:
	get_tree().current_scene = self
	sp.queue_free()
	await _frames(3)

func _check_back_story() -> void:
	print("[touch] 返回键：剧情段")
	var sp := _story(1) # 对话场景
	await _frames(4)
	_ok(sp.menu_btn.visible, "剧情段显示右上「菜单」")
	await _secs(1.0)
	await _shot("story_dialogue")
	Game.back(true)
	await _frames(2)
	await _shot("story_menu")
	_ok(is_instance_valid(sp._menu_v) and sp.layer.process_mode == Node.PROCESS_MODE_DISABLED, "返回键打开菜单并暂停对话")
	var dlg_alive := false
	for c in sp.layer.get_children():
		if c is DialogueBox:
			dlg_alive = true
	_ok(dlg_alive, "返回键没有跳过对话")
	Game.back(true)
	await _frames(2)
	_ok(not is_instance_valid(sp._menu_v) and sp.layer.process_mode == Node.PROCESS_MODE_INHERIT, "再按返回键关闭菜单")
	await _end_story(sp)

func _check_back_trade() -> void:
	print("[touch] 返回键：交易段")
	var sp := _story(2) # 交易场景（带开场对话）
	await _frames(4)
	var ts: TradeScreen = sp.trade_screen
	_ok(ts != null and not sp.menu_btn.visible, "交易段隐藏剧情菜单（用交易画面自己的）")
	# 关掉开场对话与教学说明
	for k in 30:
		for p in ts._popup_layer.get_children():
			if p is DialogueBox:
				p._end()
		for b in _buttons(ts._popup_layer):
			if b.text in ["明白了", "继续"] and b.is_visible_in_tree():
				b.pressed.emit()
		await _frames(2)
		if not ts._modal_open:
			break
	_ok(not ts._modal_open, "弹窗已关闭")
	Game.back(true)
	await _frames(2)
	await _shot("trade_pause")
	_ok(is_instance_valid(ts._pause_v) and ts.speed == 0, "返回键打开暂停菜单")
	Game.back(true)
	await _frames(2)
	_ok(not is_instance_valid(ts._pause_v) and not ts._modal_open, "再按返回键关闭暂停菜单")
	await _end_story(sp)

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out
