extends Node
## 界面冒烟测试（需要窗口）：godot --path . res://tests/smoke_ui.tscn
## 1) 肉鸽：开局 → 第一个交易节点 → 自动交易跑完 → 结算 → 回地图 → 事件/商店/休息弹窗
## 2) 剧情：逐章打开每个交易场景并快进
## 运行中出现 SCRIPT ERROR 即视为失败（看控制台输出）。

func _ready() -> void:
	await _smoke_run()
	await _smoke_story()
	print("SMOKE DONE")
	get_tree().quit()

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _smoke_run() -> void:
	print("[smoke] 肉鸽交易节点")
	Save.data = Save._default()
	Save.data.story.tutorial_done = true
	Save.unlock("friend_mochiko")
	Save.unlock("friend_mebuki")
	Save.unlock("friend_yasuko")
	Game.run = RunState.create({"broker": "overseas", "friends": ["mochiko", "mebuki", "yasuko"], "seed": 4242})
	var first: String = Game.run.available()[0]
	Game.run.enter(first)
	Game.params = {"node": first}
	var rt: Node = load("res://src/run/run_trade.tscn").instantiate()
	add_child(rt)
	await _frames(3)
	# 关掉开场对话
	for c in rt.screen._popup_layer.get_children():
		if c is DialogueBox:
			c._end()
	await _frames(2)
	var s: TradeSession = rt.session
	# 用一下仲间主动
	for f in ["mochiko", "yasuko"]:
		rt._use_friend(f, Button.new())
	var n := 0
	while not s.done and n < 2000:
		s.advance()
		n += 1
		if n % 40 == 0:
			rt.screen._select_symbol(["USDJPY", "EURJPY", "AUDJPY"][n / 40 % 3])
			rt.screen.lots = 1.0
			rt.screen.sl_pips = 30.0
			rt.screen.tp_pips = 60.0
			rt.screen._place(1 if n % 80 == 0 else -1)
		if n % 7 == 0:
			await get_tree().process_frame
	print("  节点结束 ticks=%d reason=%s money=%s" % [n, s.result.get("reason", "?"), GameDate.yen(Game.run.money)])
	await _frames(3)
	rt.queue_free()
	await _frames(2)
	# 地图 + 弹窗
	var mp: Node = load("res://src/run/run_map.tscn").instantiate()
	add_child(mp)
	await _frames(3)
	mp._open_rest()
	await _frames(2)
	mp._open_shop()
	await _frames(2)
	var ev := {"event": "mebuki_borrow"}
	mp._open_event(ev)
	await _frames(3)
	mp.queue_free()
	await _frames(2)
	print("  地图弹窗 ok")

func _smoke_story() -> void:
	print("[smoke] 剧情交易场景")
	for c in StoryDB.all():
		var scenes: Array = c.get("scenes", [])
		for i in scenes.size():
			if scenes[i].get("type", "") != "trade":
				continue
			Game.params = {"chapter": c.id, "scene_index": i}
			var sp: Node = load("res://src/story/story_player.tscn").instantiate()
			add_child(sp)
			await _frames(4)
			var ts: TradeScreen = sp.trade_screen
			if ts == null:
				printerr("  %s 场景%d 没有交易画面" % [c.id, i])
				sp.queue_free()
				continue
			# 关掉所有弹窗，快进 200 tick
			for k in 200:
				for p in ts._popup_layer.get_children():
					if p is DialogueBox:
						p._end()
				ts._modal_open = false
				if ts.session.done:
					break
				ts.session.advance()
				if k % 20 == 0:
					await get_tree().process_frame
			print("  %s 场景%d ok（tick %d, 净值 %s）" % [c.id, i, ts.session.session_tick(), GameDate.yen(ts.session.account.equity())])
			sp.queue_free()
			await _frames(2)
