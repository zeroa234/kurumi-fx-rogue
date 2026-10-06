extends Control
## 章节选择。新手教程章节带「教程」标记；章节随 data/story/chapters 自动增加。

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
	bg.texture = UI.tex("res://assets/sprites/bg/bg_room_night.png")
	bg.modulate = Color(0.45, 0.4, 0.55)
	add_child(bg)
	var head := UI.hbox(8)
	head.position = Vector2(12, 8)
	head.add_child(UI.button("← 返回", func(): Game.goto("res://src/scenes/title.tscn")))
	head.add_child(UI.label("剧情模式 —— 跟着漫画走", UI.PINK))
	add_child(head)
	var note := UI.label("前几章是新手教程；教程完成后解锁肉鸽模式。剧情按原作逐卷改编，台词为转述。", UI.DIM)
	note.position = Vector2(12, 30)
	add_child(note)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(12, 48)
	scroll.size = Vector2(616, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var v := UI.vbox(3)
	v.custom_minimum_size.x = 600
	scroll.add_child(v)
	for c in StoryDB.all():
		v.add_child(_row(c))

func _row(c: Dictionary) -> Control:
	var p := UI.panel(UI.PANEL, UI.BORDER)
	var h := UI.hbox(6)
	p.add_child(h)
	var unlocked := StoryDB.is_unlocked(c)
	var cleared := Save.story_cleared(c.id)
	var tag := "教程" if c.get("tutorial", false) else ("战役" if c.get("battle", false) else "剧情")
	var tag_col := UI.CYAN if tag == "教程" else (UI.UP if tag == "战役" else UI.DIM)
	var tl := UI.label("[%s]" % tag, tag_col)
	tl.custom_minimum_size.x = 36
	h.add_child(tl)
	var v := UI.vbox(0)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := UI.label(c.get("title", c.id), UI.TEXT if unlocked else UI.MUTED)
	v.add_child(title)
	var sub := "原作 %s" % c.get("manga", "—")
	if c.has("period"):
		sub += " · " + c.period
	if c.get("wip", false):
		sub += " · 连载中，随原作更新"
	v.add_child(UI.label(sub, UI.DIM))
	h.add_child(v)
	if cleared:
		h.add_child(UI.label("✓已读", UI.DOWN if not Save.setting("green_up", false) else UI.UP))
	var b := UI.button("开始" if not cleared else "重温", func(): Game.goto("res://src/story/story_player.tscn", {"chapter": c.id}), 52)
	b.disabled = not unlocked
	if not unlocked:
		b.text = "未解锁"
	h.add_child(b)
	return p
