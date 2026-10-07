extends Control
## 肉鸽入口：继续进行中的局，或配置新的一局（业者、仲间、挑战度、开局手法）。

var broker_id := "overseas"
var picked_friends: Array = []
var asc := 0
var start_relic := ""
var _relic_choices: Array = []
var _root: VBoxContainer

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Bgm.play("menu")
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = UI.tex("res://assets/sprites/bg/bg_city_night.png")
	bg.modulate = Color(0.5, 0.45, 0.6)
	add_child(bg)
	asc = int(Save.data.meta.get("max_ascension", 0))
	var rd: Dictionary = Save.data.get("run", {})
	if not rd.is_empty() and not rd.get("ended", false):
		_show_continue(rd)
	else:
		_show_setup()

func _clear() -> void:
	for c in get_children():
		if c is ScrollContainer or c is PanelContainer or c.name == "content":
			c.queue_free()

func _show_continue(rd: Dictionary) -> void:
	var p := UI.panel(UI.PANEL, UI.PINK)
	p.position = Vector2(160, 90)
	add_child(p)
	var v := UI.vbox(6)
	v.custom_minimum_size.x = 300
	p.add_child(v)
	v.add_child(UI.label("有一局正在进行中", UI.PINK))
	v.add_child(UI.label("第 %d 幕 · 资金 %s · 借金 %s · FP %d" % [int(rd.act), GameDate.yen(float(rd.money)), GameDate.yen(float(rd.debt)), int(rd.fp)], UI.TEXT))
	if String(rd.get("in_node", "")) != "":
		v.add_child(UI.label("（上次在交易途中退出：该节点视为放弃，メンタル -10）", UI.ORANGE))
	var h := UI.hbox(8)
	h.add_child(UI.button("继续", func():
		Game.run = RunState.from_dict(rd)
		if Game.run.in_node != "":
			Game.run.complete_current()
			Game.run.mental = maxf(1.0, Game.run.mental - 10.0)
			Game.run.save()
		Game.goto("res://src/run/run_map.tscn")))
	h.add_child(UI.button("放弃本局", func():
		var r := RunState.from_dict(rd)
		r.ended = true
		r.end_reason = "abandon"
		Game.run = r
		Game.goto("res://src/run/run_result.tscn")))
	h.add_child(UI.button("返回", func(): Game.goto("res://src/scenes/title.tscn")))
	v.add_child(h)

func _show_setup() -> void:
	var sc := ScrollContainer.new()
	sc.position = Vector2(12, 8)
	sc.size = Vector2(616, 344)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	_root = UI.vbox(5)
	_root.custom_minimum_size.x = 600
	sc.add_child(_root)
	_rebuild()

func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	var head := UI.hbox(8)
	head.add_child(UI.button("← 返回", func(): Game.goto("res://src/scenes/title.tscn")))
	head.add_child(UI.label("肉鸽模式 —— 从 30万円 到 2000万円", UI.PINK))
	_root.add_child(head)
	var sm := 300000.0 + Save.meta_level("money1") * 50000.0
	_root.add_child(UI.label("起始资金 %s　·　相場勘 %d 点（可在「局外养成」使用）" % [GameDate.yen(sm), int(Save.data.meta.points)], UI.DIM))
	# 业者
	_root.add_child(UI.label("选择 FX 业者", UI.YELLOW))
	for b in DB.get_json("res://data/run/brokers.json").brokers:
		var ok := Save.has_unlock(b.get("unlock", ""))
		var p := UI.panel(UI.PANEL2 if b.id == broker_id else UI.PANEL, UI.PINK if b.id == broker_id else UI.BORDER)
		var h := UI.hbox(6)
		var bt := UI.button(("● " if b.id == broker_id else "○ ") + b.name, func(): broker_id = b.id; _rebuild(), 120)
		bt.disabled = not ok
		h.add_child(bt)
		var d := UI.label(b.desc if ok else "（未解锁：在局外养成中开户）", UI.TEXT if ok else UI.MUTED)
		d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		d.custom_minimum_size.x = 460
		h.add_child(d)
		p.add_child(h)
		_root.add_child(p)
	# 仲间
	var slots := 1 + Save.meta_level("slots_friend")
	_root.add_child(UI.label("选择同行的仲间（%d/%d）" % [picked_friends.size(), slots], UI.YELLOW))
	var fh := UI.hbox(6)
	for f in DB.get_json("res://data/run/friends.json").friends:
		var unlocked := Save.has_unlock(f.unlock)
		var on := picked_friends.has(f.id)
		var fb := UI.button(("★ " if on else "") + (f.name if unlocked else "？？？"), func():
			if picked_friends.has(f.id):
				picked_friends.erase(f.id)
			elif picked_friends.size() < slots:
				picked_friends.append(f.id)
			_rebuild(), 120)
		fb.disabled = not unlocked
		fb.tooltip_text = ("%s\n被动：%s\n主动：%s — %s" % [f.bio, f.passive_desc, f.active.name, f.active.desc]) if unlocked else "在剧情模式中结识后解锁"
		fh.add_child(fb)
	_root.add_child(fh)
	for fid in picked_friends:
		var fd: Dictionary = DB.find("res://data/run/friends.json", "friends", fid)
		var l := UI.label("%s：%s ／ 主动「%s」%s" % [fd.name, fd.passive_desc, fd.active.name, fd.active.desc], Color(String(fd.color)))
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 590
		_root.add_child(l)
	# 开局手法
	if Save.meta_level("start_relic") > 0:
		if _relic_choices.is_empty():
			var pool: Array = []
			for r in DB.get_json("res://data/run/relics.json").relics:
				if r.rarity == "common" and r.get("unlock", "") == "":
					pool.append(r)
			pool.shuffle()
			_relic_choices = pool.slice(0, 3)
		_root.add_child(UI.label("开局手法（选 1）", UI.YELLOW))
		var rh := UI.hbox(6)
		for r in _relic_choices:
			var rb := UI.button(("● " if start_relic == r.id else "○ ") + r.name, func(): start_relic = r.id; _rebuild(), 140)
			rb.tooltip_text = r.desc
			rh.add_child(rb)
		_root.add_child(rh)
	# 挑战度
	var max_asc := int(Save.data.meta.get("max_ascension", 0))
	if max_asc > 0:
		var ah := UI.hbox(6)
		ah.add_child(UI.label("挑战度", UI.YELLOW))
		ah.add_child(UI.button("-", func(): asc = maxi(0, asc - 1); _rebuild()))
		ah.add_child(UI.label(str(asc), UI.UP if asc > 0 else UI.TEXT))
		ah.add_child(UI.button("+", func(): asc = mini(max_asc, asc + 1); _rebuild()))
		var desc := ""
		for a in DB.get_json("res://data/run/meta.json").ascension:
			if int(a.level) <= asc:
				desc += "%d.%s " % [int(a.level), a.desc]
		var dl := UI.label(desc if desc != "" else "（无额外难度）", UI.DIM)
		dl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		dl.custom_minimum_size.x = 420
		ah.add_child(dl)
		_root.add_child(ah)
	var go := UI.button("开始挑战！", _start, 160)
	go.custom_minimum_size.y = 24
	_root.add_child(go)

func _start() -> void:
	Game.run = RunState.create({"broker": broker_id, "friends": picked_friends, "ascension": asc, "start_relic": start_relic})
	Save.data.stats.runs = int(Save.data.stats.runs) + 1
	Game.run.save()
	Game.goto("res://src/run/run_map.tscn", {"intro": true})
