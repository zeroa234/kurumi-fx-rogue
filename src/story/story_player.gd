extends Control
## 剧情播放器：按章节 JSON 依次播放场景（标题卡 / 对话 / CG / 交易）。
## 章节格式见 docs/story-format.md。参数：Game.params.chapter = 章节 id。

var chapter: Dictionary
var scenes: Array = []
var idx := -1
var bg: TextureRect
var bg_fill: ColorRect
var layer: Control
var trade_screen: TradeScreen
var director: TutorialDirector
var skip_btn: Button

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_fill = ColorRect.new()
	bg_fill.color = Color("0b0814")
	bg_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg_fill)
	bg = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	add_child(bg)
	layer = Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer)
	var id: String = Game.params.get("chapter", "ch01")
	chapter = StoryDB.chapter(id)
	if chapter.is_empty():
		push_error("找不到章节 " + id)
		Game.goto("res://src/scenes/chapter_select.tscn")
		return
	scenes = chapter.get("scenes", [])
	idx = int(Game.params.get("scene_index", 0)) - 1
	battle_only = bool(Game.params.get("battle_only", false))
	battle_idx = idx + 1
	_next()

var battle_only := false
var battle_idx := 0

func _next() -> void:
	idx += 1
	_clear_layer()
	if battle_only and idx > battle_idx:
		Game.goto("res://src/scenes/battles.tscn")
		return
	if idx >= scenes.size():
		_chapter_done()
		return
	var s: Dictionary = scenes[idx]
	match String(s.get("type", "dialogue")):
		"title_card": _play_title_card(s)
		"dialogue": _play_dialogue(s)
		"cg": _play_cg(s)
		"trade": _play_trade(s)
		"unlock": _play_unlock(s)
		_: _next()

func _clear_layer() -> void:
	for c in layer.get_children():
		c.queue_free()
	trade_screen = null
	director = null

func set_bg(id: String) -> void:
	if id == "" or id == "none":
		bg.texture = null
		return
	var tex := UI.tex("res://assets/sprites/bg/%s.png" % id)
	if tex == null:
		tex = UI.tex("res://assets/sprites/cg/%s.png" % id)
	bg.texture = tex
	bg_fill.color = Color("0b0814") if tex else _fallback_color(id)

func _fallback_color(id: String) -> Color:
	if id.contains("night") or id.contains("dim"):
		return Color("0e0a1c")
	if id.contains("storm") or id.contains("rain"):
		return Color("101820")
	return Color("231a35")

# ---------------------------------------------------------------- 场景

func _play_title_card(s: Dictionary) -> void:
	set_bg(s.get("bg", "none"))
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75 if bg.texture else 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var v := UI.vbox(8)
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := UI.label(s.get("text", ""), UI.WHITE, 24)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if s.has("sub"):
		var st := UI.label(s.sub, UI.DIM)
		st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(st)
	layer.add_child(v)
	v.position = ((Vector2(640, 360) - v.get_combined_minimum_size()) / 2.0).floor()
	v.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(v, "modulate:a", 1.0, 0.6)
	tw.tween_interval(float(s.get("hold", 1.6)))
	tw.tween_property(v, "modulate:a", 0.0, 0.5)
	tw.tween_callback(_next)
	Sfx.play(s.get("sfx", "page"))

func _play_dialogue(s: Dictionary) -> void:
	set_bg(s.get("bg", "none"))
	var d := DialogueBox.new()
	d.lines = s.get("lines", [])
	d.dim_background = false
	d.bg_changed.connect(set_bg)
	d.finished.connect(_next)
	layer.add_child(d)

func _play_cg(s: Dictionary) -> void:
	set_bg(s.get("image", ""))
	if s.has("lines"):
		_play_dialogue({"lines": s.lines, "bg": s.get("image", "")})
	else:
		var b := UI.button("▼", _next)
		b.position = Vector2(610, 330)
		layer.add_child(b)

func _play_unlock(s: Dictionary) -> void:
	for u in s.get("unlocks", []):
		Save.unlock(u)
	if s.get("tutorial_done", false):
		Save.data.story.tutorial_done = true
	Save.write()
	var p := UI.panel(Color("201838"), UI.YELLOW)
	var v := UI.vbox(6)
	v.add_child(UI.label(s.get("title", "解锁！"), UI.YELLOW, 24))
	var r := UI.rich(s.get("text", ""))
	r.custom_minimum_size = Vector2(380, 0)
	v.add_child(r)
	var ok := UI.button("继续", _next)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(ok)
	p.add_child(v)
	layer.add_child(p)
	p.reset_size()
	p.position = ((Vector2(640, 360) - p.size) / 2.0).floor()
	Sfx.play("unlock")

func _play_trade(s: Dictionary) -> void:
	bg.texture = null
	var cfg: Dictionary = s.get("config", {}).duplicate(true)
	var mods := Mods.new()
	mods.set_layer("scene", s.get("mods", {}))
	var session := TradeSession.new(cfg, mods)
	# 预置持仓（剧情：接手时已有的仓位）
	for p in s.get("positions", []):
		var r = session.account.open_position(p.symbol, int(p.side), float(p.lots), float(p.get("sl", 0.0)), float(p.get("tp", 0.0)))
		if r is Account.Position and p.has("entry"):
			(r as Account.Position).entry = float(p.entry)
	trade_screen = TradeScreen.new(session)
	trade_screen.auto_close_on_finish = bool(s.get("close_at_end", true))
	trade_screen.exit_label = "返回章节选择"
	trade_screen.exit_cb = func(): Game.goto("res://src/scenes/chapter_select.tscn")
	layer.add_child(trade_screen)
	trade_screen._set_speed(int(s.get("speed", 0)), true)
	director = TutorialDirector.new(trade_screen, s.get("steps", []))
	layer.add_child(director)
	trade_screen.session_done.connect(_on_trade_done.bind(s))
	if s.has("intro"):
		trade_screen._on_script_dialog(s.intro)
		await _wait_modal()
	director.start()

func _wait_modal() -> void:
	while trade_screen and trade_screen._modal_open:
		await get_tree().process_frame

func _on_trade_done(result: Dictionary, s: Dictionary) -> void:
	var won := _judge(result, s.get("win", {}))
	var lines: Array = s.get("on_win" if won else "on_lose", [])
	var summary := "结果：%s\n净值 %s（起始 %s）\n交易 %d 次，胜 %d 次" % [
		{"time": "时间到", "goal": "达成目标", "bust": "资金耗尽", "broken": "心态崩溃", "quit": "中止"}.get(result.reason, result.reason),
		GameDate.yen(result.equity), GameDate.yen(result.start), int(result.stats.trades), int(result.stats.wins)]
	if result.debt > 0.0:
		summary += "\n[color=#ff5d73]不足金（借金）%s[/color]" % GameDate.yen(result.debt)
	Save.data.stats.total_trades = int(Save.data.stats.total_trades) + int(result.stats.trades)
	trade_screen.show_message(summary, func():
		if not lines.is_empty():
			trade_screen._on_script_dialog(lines)
			await _wait_modal()
		if won or s.get("lose_continues", false):
			_next()
		else:
			_retry_prompt()
	)

func _judge(result: Dictionary, win: Dictionary) -> bool:
	if win.is_empty() or win.get("always", false):
		return true
	if win.has("steps") and director and not director.all_done():
		return false
	if win.has("equity") and float(result.equity) < float(win.equity):
		return false
	if win.has("profit") and float(result.equity) - float(result.start) < float(win.profit):
		return false
	if win.has("no_debt") and float(result.debt) > 0.0:
		return false
	if result.reason in ["bust", "broken"] and not win.get("allow_bust", false):
		return false
	return true

func _retry_prompt() -> void:
	var p := UI.panel(Color("201838"), UI.UP)
	var v := UI.vbox(6)
	v.add_child(UI.label("没能达成目标……", UI.UP))
	var h := UI.hbox(8)
	h.add_child(UI.button("再来一次", func():
		idx -= 1
		_next()
	))
	h.add_child(UI.button("返回章节选择", func(): Game.goto("res://src/scenes/chapter_select.tscn")))
	v.add_child(h)
	p.add_child(v)
	layer.add_child(p)
	p.reset_size()
	p.position = ((Vector2(640, 360) - p.size) / 2.0).floor()

func _chapter_done() -> void:
	var id: String = chapter.get("id", "")
	Save.mark_story(id)
	for u in chapter.get("unlock_on_clear", []):
		Save.unlock(u)
	if chapter.get("tutorial_complete", false):
		Save.data.story.tutorial_done = true
	Save.write()
	var nxt := StoryDB.next_of(id)
	var p := UI.panel(Color("201838"), UI.PINK)
	var v := UI.vbox(6)
	v.add_child(UI.label("%s  完" % chapter.get("title", ""), UI.PINK))
	if chapter.has("manga"):
		v.add_child(UI.label("对应原作：%s" % chapter.manga, UI.DIM))
	var h := UI.hbox(8)
	if nxt != "":
		h.add_child(UI.button("下一章", func(): Game.goto("res://src/story/story_player.tscn", {"chapter": nxt})))
	h.add_child(UI.button("章节选择", func(): Game.goto("res://src/scenes/chapter_select.tscn")))
	h.add_child(UI.button("标题画面", func(): Game.goto("res://src/scenes/title.tscn")))
	v.add_child(h)
	p.add_child(v)
	layer.add_child(p)
	p.reset_size()
	p.position = ((Vector2(640, 360) - p.size) / 2.0).floor()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and trade_screen == null:
		pass
