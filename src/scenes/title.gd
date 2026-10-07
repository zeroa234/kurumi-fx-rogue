extends Control
## 标题画面。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = UI.tex("res://assets/sprites/cg/cg_title.png")
	if bg.texture == null:
		bg.texture = UI.tex("res://assets/sprites/bg/bg_title.png")
	add_child(bg)
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.02, 0.08, 0.35)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	_build_logo()
	_build_menu()
	var foot := UI.label("非官方同人游戏 · 原作《FX戦士くるみちゃん》でむにゃん / 炭酸だいすき（KADOKAWA）", UI.DIM)
	foot.position = Vector2(8, 344)
	add_child(foot)
	var ver := UI.label("v0.1", UI.MUTED)
	ver.position = Vector2(608, 344)
	add_child(ver)
	Sfx.play("title")

func _build_logo() -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.06, 0.03, 0.1, 0.8), UI.PINK, 1, 6))
	p.position = Vector2(16, 18)
	var v := UI.vbox(2)
	v.add_child(UI.label("FX战士久留美", UI.PINK, 24))
	v.add_child(UI.label("同人 · 2000万之路", UI.YELLOW))
	v.add_child(UI.label("FX戦士くるみちゃん  Fan Game", UI.DIM))
	p.add_child(v)
	add_child(p)

func _build_menu() -> void:
	var v := UI.vbox(4)
	v.position = Vector2(470, 104)
	add_child(v)
	var tut: bool = Save.data.story.tutorial_done
	var items := [
		["剧情模式", func(): Game.goto("res://src/scenes/chapter_select.tscn"), true, ""],
		["肉鸽模式", func(): Game.goto("res://src/run/run_hub.tscn"), tut, "完成剧情模式的新手教程后解锁"],
		["局外养成", func(): Game.goto("res://src/run/meta_screen.tscn"), tut, "完成新手教程后解锁"],
		["经典战役", func(): Game.goto("res://src/scenes/battles.tscn"), true, ""],
		["图鉴", func(): Game.goto("res://src/scenes/codex.tscn"), tut, "完成新手教程后解锁"],
		["设置", func(): Game.goto("res://src/scenes/settings.tscn"), true, ""],
		["退出", func(): get_tree().quit(), true, ""],
	]
	if OS.has_feature("web"):
		items.pop_back() # 网页版关不掉浏览器标签，去掉「退出」
	for it in items:
		var b := UI.button(it[0], it[1], 150)
		b.custom_minimum_size.y = 22
		if not it[2]:
			b.disabled = true
			b.tooltip_text = it[3]
			b.text = it[0] + "（未解锁）"
		v.add_child(b)

func _unhandled_input(event: InputEvent) -> void:
	# 开发者：F9 解锁全部（测试用）
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9 and event.shift_pressed:
		Save.data.story.tutorial_done = true
		for c in StoryDB.all():
			Save.mark_story(c.id)
		Save.write()
		get_tree().reload_current_scene()
