extends Control
## 经典战役：重玩剧情中带 battle 标记的交易场景（需先在剧情模式中读到）。
## 以后可以在 data/battles/ 加入独立的复刻战役。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var head := UI.hbox(8)
	head.position = Vector2(12, 8)
	head.add_child(UI.button("← 返回", func(): Game.goto("res://src/scenes/title.tscn")))
	head.add_child(UI.label("经典战役 —— 漫画中的名场面行情", UI.PINK))
	add_child(head)
	var v := UI.vbox(4)
	v.position = Vector2(12, 36)
	v.custom_minimum_size.x = 600
	add_child(v)
	var any := false
	for c in StoryDB.all():
		var scenes: Array = c.get("scenes", [])
		for i in scenes.size():
			var s: Dictionary = scenes[i]
			if s.get("type", "") != "trade" or not (c.get("battle", false) or s.get("battle", false)):
				continue
			any = true
			var ok := Save.story_cleared(c.id)
			var h := UI.hbox(8)
			var title: String = s.get("battle_title", c.get("title", ""))
			var l := UI.label("%s（%s · %s）" % [title, c.get("manga", ""), c.get("period", "")], UI.TEXT if ok else UI.MUTED)
			l.custom_minimum_size.x = 480
			h.add_child(l)
			var b := UI.button("挑战" if ok else "剧情中解锁", func(): Game.goto("res://src/story/story_player.tscn", {"chapter": c.id, "scene_index": i, "battle_only": true}), 90)
			b.disabled = not ok
			h.add_child(b)
			v.add_child(h)
	if not any:
		v.add_child(UI.label("还没有可挑战的战役。推进剧情模式吧。", UI.DIM))
	var note := UI.label("经典战役重现漫画中的真实行情事件（关键价位来自公开报道），剧情模式读到后即可在这里反复挑战。", UI.DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	note.custom_minimum_size.x = 600
	note.position = Vector2(12, 320)
	add_child(note)
