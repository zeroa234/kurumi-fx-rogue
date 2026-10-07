extends Control
## 设置。

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var v := UI.vbox(6)
	v.position = Vector2(40, 24)
	add_child(v)
	v.add_child(UI.label("设置", UI.PINK, 24))
	_toggle(v, "重大新闻时自动暂停", "auto_pause_news", true)
	_toggle(v, "重要指标发布前自动暂停", "auto_pause_indicator", true)
	_toggle(v, "维持率告警时自动暂停", "auto_pause_margin", true)
	_toggle(v, "画面震动", "screen_shake", true)
	_toggle(v, "国际配色（绿涨红跌，重启后生效）", "green_up", false)
	var h := UI.hbox(6)
	h.add_child(UI.label("音效音量", UI.TEXT))
	var sl := HSlider.new()
	sl.custom_minimum_size = Vector2(160, 12)
	sl.min_value = 0.0
	sl.max_value = 1.0
	sl.step = 0.1
	sl.value = float(Save.setting("sfx", 0.8))
	sl.value_changed.connect(func(x): Save.data.settings.sfx = x; Sfx.play("click"))
	h.add_child(sl)
	v.add_child(h)
	if Game.touch:
		v.add_child(UI.label("对话：轻点继续 · 长按快进 · 右上「快进」「跳过」", UI.DIM))
		v.add_child(UI.label("交易：右上「菜单」或返回键＝暂停菜单 · 长按按钮看说明", UI.DIM))
		v.add_child(UI.label("图表：拖空白处平移 · 双指缩放 · 拖持仓的 SL/TP 线可直接改单", UI.DIM))
	else:
		var fs := UI.button("切换全屏（F11）", func():
			var f := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if f else DisplayServer.WINDOW_MODE_FULLSCREEN))
		v.add_child(fs)
		v.add_child(UI.label("快捷键：空格 暂停/继续 · 1~4 速度 · B 买 · S 卖 · C 全部平仓 · Tab 切换品种 · Esc 菜单", UI.DIM))
		v.add_child(UI.label("图表：滚轮缩放 · 右键拖动平移 · 左键拖动持仓的 SL/TP 线可直接改单 · 对话按住 Ctrl 快进", UI.DIM))
	# 二次确认：手机上误触一下就清档太危险
	var danger := UI.button("清除全部存档", func():
		var m := UI.modal(self, UI.UP, 260)
		m.add_child(UI.label("确定清除全部存档吗？无法恢复。", UI.UP))
		var h2 := UI.hbox(8)
		var yes := UI.button("清除", func():
			Save.reset_all()
			Game.goto("res://src/scenes/title.tscn"))
		yes.add_theme_color_override("font_color", UI.UP)
		h2.add_child(yes)
		h2.add_child(UI.button("取消", func(): UI.close_modal(m)))
		m.add_child(h2))
	danger.add_theme_color_override("font_color", UI.UP)
	v.add_child(danger)
	v.add_child(UI.button("← 返回", func():
		Save.write()
		Game.goto("res://src/scenes/title.tscn")))

func _toggle(v: VBoxContainer, text: String, key: String, def: bool) -> void:
	var c := CheckButton.new()
	c.text = text
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = bool(Save.setting(key, def))
	c.toggled.connect(func(on): Save.data.settings[key] = on; Save.write())
	v.add_child(c)
