extends Node
## 真实时间检查「自动播放段」（速度被剧本锁定的交易场景）：
## 只点掉对话框/说明框，从不按速度键，确认时间会一直走到场景结束，不会被自动暂停卡死。
## godot --path . res://tests/autoplay_check.tscn

const CHAPTERS := ["ch01", "ch04", "ch11", "ch12"]

func _ready() -> void:
	Engine.time_scale = 12.0
	var bad := 0
	for ch in CHAPTERS:
		var c := StoryDB.chapter(ch)
		for i in c.scenes.size():
			if c.scenes[i].type == "trade":
				if not await _check(ch, i):
					bad += 1
	Engine.time_scale = 1.0
	print("AUTOPLAY CHECK: %d stalled" % bad)
	get_tree().quit(1 if bad > 0 else 0)

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out

func _check(ch: String, idx: int) -> bool:
	Game.params = {"chapter": ch, "scene_index": idx}
	var sp: Node = load("res://src/story/story_player.tscn").instantiate()
	add_child(sp)
	await get_tree().process_frame
	var ts: TradeScreen = sp.trade_screen
	var last_tick := -1
	var still := 0.0
	var t0 := Time.get_ticks_msec()
	var ok := true
	while Time.get_ticks_msec() - t0 < 90000:
		await get_tree().process_frame
		if not is_instance_valid(ts) or ts.finished:
			break
		# 玩家只会点对话/说明，不碰速度
		for p in ts._popup_layer.get_children():
			if p is DialogueBox:
				p._advance()
		for b in _buttons(ts._popup_layer):
			if b.text == "明白了" and b.is_visible_in_tree():
				b.pressed.emit()
		var d: TutorialDirector = sp.director
		var waiting_player := false
		if d and d.i < d.steps.size():
			var t: String = String(d._cond.get("type", ""))
			waiting_player = t in ["open", "close", "sl_set", "tp_set", "tab", "equity", "flat"]
		var tk := ts.session.market.tick
		if tk != last_tick or ts._modal_open or waiting_player:
			last_tick = tk
			still = 0.0
		else:
			still += get_process_delta_time()
			if still > 3.0:
				printerr("%s 场景%d：时间停住了（%s，speed=%d，locked=%s）" % [ch, idx, ts.session.now_text(), ts.speed, ts.locked.get("speed", false)])
				ok = false
				break
	var done: bool = not is_instance_valid(ts) or ts.finished
	print("%s 场景%d：%s  结束=%s" % [ch, idx, "OK" if ok else "STALL", done])
	sp.queue_free()
	await get_tree().process_frame
	return ok
