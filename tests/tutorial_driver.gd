extends Node
## 教程自动通关：godot --path . res://tests/tutorial_driver.tscn [-- --chapter=ch03]
## 按每一步 until 条件模拟玩家操作，检查教学步骤能否全部走完（不会卡死）。

var report: Array = []

func _ready() -> void:
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="): only = a.substr(10)
	for c in StoryDB.all():
		if only != "" and c.id != only:
			continue
		if only == "" and not c.get("tutorial", false):
			continue
		var scenes: Array = c.scenes
		for i in scenes.size():
			if scenes[i].type == "trade" and not scenes[i].get("steps", []).is_empty():
				await _drive(c.id, i)
	for r in report:
		print(r)
	print("TUTORIAL DRIVER DONE")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _close_modals(ts: TradeScreen) -> void:
	for p in ts._popup_layer.get_children():
		if p is DialogueBox:
			p._end()
	for b in _buttons(ts._popup_layer):
		if b.text in ["明白了", "继续"] and b.is_visible_in_tree():
			b.pressed.emit()

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out

func _drive(ch: String, idx: int) -> void:
	Game.params = {"chapter": ch, "scene_index": idx}
	var sp: Node = load("res://src/story/story_player.tscn").instantiate()
	add_child(sp)
	await _frames(4)
	var ts: TradeScreen = sp.trade_screen
	var dir: TutorialDirector = sp.director
	var guard := 0
	var last_step := -1
	var stuck := 0
	while guard < 6000:
		guard += 1
		await _close_modals(ts)
		await get_tree().process_frame
		if dir == null or not is_instance_valid(ts) or ts.finished:
			break
		if dir.i >= dir.steps.size():
			break
		if dir.i != last_step:
			last_step = dir.i
			stuck = 0
		stuck += 1
		var c: Dictionary = dir._cond
		_act(ts, c)
		# 推进时间（不受锁定限制，模拟玩家按下播放）
		if not ts._modal_open and not ts.session.done:
			ts.session.advance()
		if stuck > 1500:
			report.append("%s 场景%d：卡在第 %d 步（until=%s）" % [ch, idx, dir.i, JSON.stringify(c)])
			break
	var res := "%s 场景%d：步骤 %d/%d，session.done=%s，净值 %s" % [ch, idx, mini(dir.i, dir.steps.size()), dir.steps.size(), ts.session.done if is_instance_valid(ts) else "?", GameDate.yen(ts.session.account.equity()) if is_instance_valid(ts) else "?"]
	report.append(res)
	print(res)
	sp.queue_free()
	await _frames(2)

func _act(ts: TradeScreen, c: Dictionary) -> void:
	var acc := ts.session.account
	match String(c.get("type", "")):
		"open":
			if c.has("symbol"):
				ts._select_symbol(c.symbol)
			ts.lots = maxf(float(c.get("min_lots", 0.1)), ts.lots)
			if acc.positions.is_empty():
				var side := int(c.get("side", 1))
				ts._place(side)
		"close":
			for p in acc.positions.duplicate():
				if not c.get("profit", false) or acc.floating(p) > 0.0:
					ts.close_pos(p)
			if acc.positions.is_empty() and c.get("profit", false) and not ts.session.done:
				# 没有仓位却要求盈利平仓：再开一单
				ts._place(1)
		"sl_set":
			ts.sl_pips = 50.0
			for p in acc.positions:
				ts._apply_sltp(p)
		"tp_set":
			ts.tp_pips = 150.0
			ts.sl_pips = 50.0
			for p in acc.positions:
				ts._apply_sltp(p)
		"any", "all":
			for sub in c.get("of", []):
				_act(ts, sub)
		"tab":
			ts._tabbar.current_tab = int(c.index)
		"equity":
			# 简单顺势：没仓位就按 1 小时动量开仓
			if acc.positions.is_empty():
				var ins := ts.session.market.get_ins(ts.selected)
				var n := ins.c.size()
				var side := 1 if ins.c[n - 1] >= ins.c[maxi(0, n - 8)] else -1
				ts.lots = maxf(1.0, floorf(acc.max_lots(ts.selected) * 0.25))
				ts.sl_pips = 30.0
				ts.tp_pips = 60.0
				ts._place(side)
