extends Control
## 图鉴：手法、道具、事件、Boss、仲间。在肉鸽中遇到过才会显示详情。

var tabs: TabBar
var body: VBoxContainer
var count_lbl: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	Bgm.play("menu")
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var head := UI.hbox(8)
	head.position = Vector2(10, 6)
	head.add_child(UI.button("← 返回", func(): Game.goto("res://src/scenes/title.tscn")))
	head.add_child(UI.label("图鉴", UI.PINK))
	count_lbl = UI.label("", UI.DIM)
	head.add_child(count_lbl)
	add_child(head)
	tabs = TabBar.new()
	tabs.position = Vector2(10, 28)
	tabs.focus_mode = Control.FOCUS_NONE
	for t in ["手法", "道具", "事件", "Boss", "仲间"]:
		tabs.add_tab(t)
	tabs.tab_changed.connect(func(_i): _refresh())
	add_child(tabs)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 48)
	sc.size = Vector2(620, 304)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	body = UI.vbox(3)
	body.custom_minimum_size.x = 604
	sc.add_child(body)
	_refresh()

func _refresh() -> void:
	for c in body.get_children():
		c.queue_free()
	match tabs.current_tab:
		0: _list(DB.get_json("res://data/run/relics.json").relics, "relics", true)
		1: _list(DB.get_json("res://data/run/items.json").items, "items", true)
		2: _events()
		3: _bosses()
		4: _friends()

func _list(items: Array, key: String, icons: bool) -> void:
	var seen: Array = Save.data.codex.get(key, [])
	count_lbl.text = "已发现 %d / %d" % [seen.size(), items.size()]
	for it in items:
		var known := seen.has(it.id)
		var h := UI.hbox(6)
		if icons:
			var t := TextureRect.new()
			t.texture = UI.icon(it.get("icon", ""), "star")
			t.custom_minimum_size = Vector2(32, 32)
			t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			t.modulate = Color.WHITE if known else Color(0, 0, 0, 0.8)
			h.add_child(t)
		var rar: String = {"common": "普通", "uncommon": "优秀", "rare": "稀有"}.get(it.get("rarity", ""), "")
		var l := UI.label(("%s %s\n%s" % [it.name, ("〔%s〕" % rar) if rar != "" else "", it.desc]) if known else "？？？\n（在肉鸽中获得后解锁）", UI.TEXT if known else UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 560
		h.add_child(l)
		body.add_child(h)

func _events() -> void:
	var evs: Array = DB.get_json("res://data/run/events.json").events
	var seen: Array = Save.data.codex.get("events", [])
	count_lbl.text = "已发现 %d / %d" % [seen.size(), evs.size()]
	for e in evs:
		var known := seen.has(e.id)
		var l := UI.label(("【%s】%s" % [e.title, String(e.text).replace("\n", " ")]) if known else "【？？？】", UI.TEXT if known else UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 600
		body.add_child(l)

func _bosses() -> void:
	var bs: Array = DB.get_json("res://data/run/nodes.json").bosses
	var seen: Array = Save.data.codex.get("bosses", [])
	count_lbl.text = "已击败 %d / %d" % [seen.size(), bs.size()]
	for b in bs:
		var known := seen.has(b.id)
		var l := UI.label(("第%d幕 BOSS「%s」：%s" % [int(b.act), b.name, b.desc]) if known else "第%d幕 BOSS「？？？」" % int(b.act), UI.TEXT if known else UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 600
		body.add_child(l)

func _friends() -> void:
	var fs: Array = DB.get_json("res://data/run/friends.json").friends
	count_lbl.text = ""
	for f in fs:
		var known := Save.has_unlock(f.unlock)
		var h := UI.hbox(6)
		var t := TextureRect.new()
		t.texture = Portraits.small(f.id, "normal")
		t.custom_minimum_size = Vector2(64, 64)
		t.modulate = Color.WHITE if known else Color(0, 0, 0, 0.85)
		h.add_child(t)
		var l := UI.label(("%s\n%s\n被动：%s\n主动「%s」：%s" % [f.name, f.bio, f.passive_desc, f.active.name, f.active.desc]) if known else "？？？\n（在剧情模式中结识后解锁）", Color(String(f.color)) if known else UI.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		l.custom_minimum_size.x = 520
		h.add_child(l)
		body.add_child(h)
