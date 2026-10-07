extends Control
## 一局结束：结算相場勘点数、统计，清空进行中的局。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var run: RunState = Game.run
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	if run == null:
		Game.goto("res://src/scenes/title.tscn")
		return
	var victory := run.end_reason == "victory"
	Bgm.play("victory" if victory else "gameover")
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = UI.tex("res://assets/sprites/cg/%s.png" % ("cg_win" if victory else "cg_shock"))
	bg.modulate = Color(0.5, 0.45, 0.6)
	add_child(bg)
	var pts := run.meta_points()
	if not run.used_specials.has("points_paid"):
		run.used_specials["points_paid"] = true
		Save.data.meta.points = int(Save.data.meta.points) + pts
		Save.data.meta.total_points = int(Save.data.meta.total_points) + pts
		Save.data.stats.best_equity = maxf(float(Save.data.stats.best_equity), run.max_net)
		var deaths: Dictionary = Save.data.stats.deaths
		deaths[run.end_reason] = int(deaths.get(run.end_reason, 0)) + 1
		if victory:
			Save.data.stats.clears = int(Save.data.stats.clears) + 1
			Save.data.meta.max_ascension = maxi(int(Save.data.meta.max_ascension), mini(10, run.ascension + 1))
		Save.data.run = {}
		Save.write()
	var v := UI.modal(self, UI.PINK if victory else UI.UP, 400, 0.3)
	var reason: String = {
		"victory": "通关！2000万円，取回来了。",
		"target": "没能达到本幕目标……",
		"broken": "心，折断了。",
		"bankrupt": "资金耗尽。",
		"abandon": "放弃了这一局。",
	}.get(run.end_reason, run.end_reason)
	v.add_child(UI.label(reason, UI.PINK if victory else UI.UP, 24))
	var face := "happy" if victory else "cry"
	var h := UI.hbox(8)
	var por := TextureRect.new()
	por.texture = Portraits.small("kurumi", face)
	por.custom_minimum_size = Vector2(64, 64)
	h.add_child(por)
	var t := "到达 第%d幕 · 节点 %d · 交易日 %d\n" % [run.act, run.nodes_cleared, run.days_elapsed]
	t += "最高净资产 %s\n" % GameDate.yen(run.max_net)
	t += "交易 %d 次 · 胜率 %d%% · 强平 %d 次\n" % [run.trades, int(100.0 * run.wins / maxf(1.0, run.trades)), run.stopouts]
	t += "手法 %d 个 · 击败 Boss %d 个\n" % [run.relics.size(), run.bosses_beaten.size()]
	t += "\n获得 [color=#ffd166]相場勘 %d 点[/color]（现有 %d）" % [pts, int(Save.data.meta.points)]
	if pts == 0 and not victory:
		t += "\n[color=#a89cc8]（至少完成 1 个节点、做过 1 笔交易才有相場勘）[/color]"
	# 富文本自动换行：放在 HBox 里必须给宽度，否则最小宽度为 0、逐字换行把弹窗撑出屏幕
	var info := UI.rich(t)
	info.custom_minimum_size.x = 328
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(info)
	v.add_child(h)
	if not victory:
		var tip := UI.label(_tip(run), UI.DIM)
		tip.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		tip.custom_minimum_size.x = 400
		v.add_child(tip)
	var bh := UI.hbox(8)
	bh.add_child(UI.button("局外养成", func(): Game.goto("res://src/run/meta_screen.tscn")))
	bh.add_child(UI.button("再来一局", func(): Game.goto("res://src/run/run_hub.tscn")))
	bh.add_child(UI.button("标题画面", func(): Game.goto("res://src/scenes/title.tscn")))
	v.add_child(bh)
	Game.run = null

func _tip(run: RunState) -> String:
	match run.end_reason:
		"broken": return "提示：メンタル也是资源。休息节点、道具、风控手法都能帮忙。"
		"bankrupt": return "提示：高杠杆满仓时，一次逆行就会被强平。手数小一点，记得止损。"
		"target": return "提示：局外养成能提高起始资金和各种能力；情报类手法让你更早看见行情。"
	return ""
