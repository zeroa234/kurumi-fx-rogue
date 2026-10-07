extends Control
## 局外养成「相場勘」。

var grid: GridContainer
var pts_lbl: Label
var info: RichTextLabel

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
	bg.texture = UI.tex("res://assets/sprites/bg/bg_lecture.png")
	bg.modulate = Color(0.4, 0.38, 0.5)
	add_child(bg)
	var head := UI.hbox(8)
	head.position = Vector2(10, 6)
	head.add_child(UI.button("← 返回", func(): Game.goto("res://src/scenes/title.tscn")))
	head.add_child(UI.label("局外养成「相場勘」", UI.PINK))
	pts_lbl = UI.label("", UI.YELLOW)
	head.add_child(pts_lbl)
	add_child(head)
	var sc := ScrollContainer.new()
	sc.position = Vector2(10, 28)
	sc.size = Vector2(620, 282)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(sc)
	grid = GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	sc.add_child(grid)
	info = UI.rich()
	info.position = Vector2(10, 314)
	info.custom_minimum_size = Vector2(620, 40)
	add_child(info)
	_refresh()

func _refresh() -> void:
	pts_lbl.text = "相場勘 %d 点" % int(Save.data.meta.points)
	for c in grid.get_children():
		c.queue_free()
	for n in DB.get_json("res://data/run/meta.json").nodes:
		grid.add_child(_card(n))
	var st: Dictionary = Save.data.stats
	info.text = "[color=#a89cc8]累计 %d 局 · 通关 %d 次 · 最高净资产 %s · 最高挑战度 %d[/color]" % [int(st.runs), int(st.clears), GameDate.yen(float(st.best_equity)), int(Save.data.meta.max_ascension)]

func _card(n: Dictionary) -> Control:
	var lv := Save.meta_level(n.id)
	var costs: Array = n.cost
	var maxed := lv >= costs.size()
	var req_ok := true
	for r in n.get("requires", []):
		if Save.meta_level(r) <= 0:
			req_ok = false
	var p := UI.panel(UI.PANEL2 if lv > 0 else UI.PANEL, UI.YELLOW if maxed else UI.BORDER)
	p.custom_minimum_size = Vector2(202, 58)
	var v := UI.vbox(1)
	p.add_child(v)
	var t := UI.label("%s  %d/%d" % [n.name, lv, costs.size()], UI.YELLOW if maxed else UI.TEXT)
	v.add_child(t)
	var d := UI.label(n.desc, UI.DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	d.custom_minimum_size.x = 194
	v.add_child(d)
	if not maxed:
		var cost := int(costs[lv])
		var b := UI.button("提升（%d 点）" % cost if req_ok else "需要前置", func():
			if int(Save.data.meta.points) >= cost:
				Save.data.meta.points = int(Save.data.meta.points) - cost
				Save.data.meta.levels[n.id] = lv + 1
				var eff: Dictionary = n.get("effect", {})
				if eff.has("unlock"):
					Save.unlock(eff.unlock)
				Save.write()
				Sfx.play("unlock")
				_refresh())
		b.disabled = not req_ok or int(Save.data.meta.points) < cost
		v.add_child(b)
	return p
