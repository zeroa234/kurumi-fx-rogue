class_name TradeScreen
extends Control
## 交易主界面。由剧情/肉鸽场景创建并传入 TradeSession。
##
## 布局（640x360）：顶栏 16 / 图表 456x222 / 右栏 184x330 / 久留美+信息页 / 底部新闻条 14

signal session_done(result: Dictionary)
signal objective_event(kind: String, data: Dictionary)

const SPEEDS := [0.0, 2.0, 5.0, 12.0, 30.0] # tick/秒
const TFS := [[1, "15分"], [4, "1时"], [16, "4时"], [96, "日"]]

var session: TradeSession
var chart: ChartView
var speed := 1
var _acc := 0.0
var selected := "USDJPY"
var lots := 1.0
var sl_pips := 0.0
var tp_pips := 0.0
var trail := false
var locked := {}
var controls := {}
var finished := false
var auto_close_on_finish := true
var hold_for_objective := false

# 节点
var _top_date: Label
var _top_session: Label
var _top_equity: Label
var _top_goal: Label
var _mental_bar: ProgressBar
var _mental_lbl: Label
var _speed_btns: Array[Button] = []
var _watch_box: VBoxContainer
var _watch_rows := {}
var _lots_lbl: Label
var _sl_lbl: Label
var _tp_lbl: Label
var _buy_btn: Button
var _sell_btn: Button
var _acct_lbl: RichTextLabel
var _tabbar: TabBar
var _tab_body: VBoxContainer
var _tab_scroll: ScrollContainer
var _portrait: TextureRect
var _portrait_frame: PanelContainer
var _bubble: PanelContainer
var _bubble_lbl: Label
var _bubble_t := 0.0
var _ticker: Label
var _ticker_clip: Control
var _ticker_x := 640.0
var _popup_layer: Control
var _breaking: PanelContainer
var _breaking_t := 0.0
var _objective: PanelContainer
var _objective_lbl: RichTextLabel
var _tf_btns: Array[Button] = []
var _trail_btn: Button
var _last_pos_count := -1
var _tab_dirty := true
var _hint_lbl: Label
var _modal_open := false

func _init(s: TradeSession) -> void:
	session = s

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	selected = session.symbols[0] if not session.symbols.is_empty() else "USDJPY"
	speed = clampi(int(Save.setting("speed", 1)), 1, 4)
	_build()
	_connect()
	_refresh_all()

# ================================================================ 构建

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_build_top()
	chart = ChartView.new()
	chart.session = session
	chart.symbol = selected
	chart.position = Vector2(0, 17)
	chart.size = Vector2(455, 221)
	add_child(chart)
	_build_tf_buttons()
	_build_right()
	_build_bottom()
	_build_ticker()
	_popup_layer = Control.new()
	_popup_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_popup_layer)
	_build_bubble()
	_build_breaking()
	_build_objective()

func _build_top() -> void:
	var bar := UI.panel(Color("140f22"), UI.BORDER)
	bar.position = Vector2(0, 0)
	bar.size = Vector2(640, 17)
	bar.add_theme_stylebox_override("panel", UI.box(Color("140f22"), UI.BORDER, 1, 1))
	add_child(bar)
	var h := UI.hbox(4)
	bar.add_child(h)
	_top_date = UI.label("", UI.TEXT)
	_top_date.custom_minimum_size.x = 122
	h.add_child(_top_date)
	_top_session = UI.label("", UI.DIM)
	_top_session.custom_minimum_size.x = 50
	h.add_child(_top_session)
	for i in SPEEDS.size():
		var t: String = ["Ⅱ", "1", "2", "3", "4"][i]
		var b := UI.button(t, _set_speed.bind(i))
		b.custom_minimum_size = Vector2(14, 13)
		b.add_theme_stylebox_override("normal", UI.box(UI.PANEL2, UI.BORDER, 1, 0))
		b.add_theme_stylebox_override("hover", UI.box(Color("3d3060"), UI.BORDER_HI, 1, 0))
		b.add_theme_stylebox_override("pressed", UI.box(Color("4a3a75"), UI.PINK, 1, 0))
		b.tooltip_text = ["暂停 (空格)", "1倍速 (1)", "2倍速 (2)", "3倍速 (3)", "4倍速 (4)"][i]
		_speed_btns.append(b)
		h.add_child(b)
	controls["speed"] = _speed_btns[1]
	h.add_child(_fixed(Control.new(), 4))
	var hi := PixelIcons.texture_rect("heart")
	hi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hi)
	_mental_bar = ProgressBar.new()
	_mental_bar.custom_minimum_size = Vector2(50, 8)
	_mental_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_mental_bar.show_percentage = false
	_mental_bar.max_value = 100
	h.add_child(_mental_bar)
	_mental_lbl = UI.label("", UI.PINK)
	_mental_lbl.custom_minimum_size.x = 20
	h.add_child(_mental_lbl)
	_top_equity = UI.label("", UI.TEXT)
	_top_equity.custom_minimum_size.x = 96
	h.add_child(_top_equity)
	_top_goal = UI.label("", UI.YELLOW)
	_top_goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top_goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_top_goal)

func _build_tf_buttons() -> void:
	var h := UI.hbox(1)
	h.position = Vector2(286, 18)
	add_child(h)
	for i in TFS.size():
		var b := UI.button(TFS[i][1], _set_tf.bind(i))
		b.custom_minimum_size = Vector2(30, 12)
		b.add_theme_stylebox_override("normal", UI.box(Color("1d1530"), UI.BORDER, 1, 0))
		b.add_theme_stylebox_override("hover", UI.box(Color("3d3060"), UI.BORDER_HI, 1, 0))
		b.add_theme_stylebox_override("pressed", UI.box(Color("4a3a75"), UI.PINK, 1, 0))
		_tf_btns.append(b)
		h.add_child(b)
	_set_tf(1)

func _build_right() -> void:
	var p := UI.panel(UI.PANEL, UI.BORDER)
	p.position = Vector2(456, 17)
	p.size = Vector2(184, 330)
	add_child(p)
	var v := UI.vbox(2)
	p.add_child(v)
	# 自选
	_watch_box = UI.vbox(0)
	v.add_child(_watch_box)
	for s in session.symbols:
		var row := Button.new()
		row.focus_mode = Control.FOCUS_NONE
		row.custom_minimum_size = Vector2(176, 13)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_stylebox_override("normal", UI.box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 1))
		row.add_theme_stylebox_override("hover", UI.box(Color("2f2450"), Color(0, 0, 0, 0), 0, 1))
		row.add_theme_stylebox_override("pressed", UI.box(Color("3d3060"), Color(0, 0, 0, 0), 0, 1))
		row.pressed.connect(_select_symbol.bind(s))
		var hl := UI.hbox(2)
		hl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hl.set_anchors_preset(Control.PRESET_FULL_RECT)
		row.add_child(hl)
		var n := UI.label(s, UI.TEXT)
		n.custom_minimum_size.x = 50
		var pr := UI.label("", UI.TEXT)
		pr.custom_minimum_size.x = 66
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var ch := UI.label("", UI.DIM)
		ch.custom_minimum_size.x = 52
		ch.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for l in [n, pr, ch]:
			l.mouse_filter = Control.MOUSE_FILTER_IGNORE
			hl.add_child(l)
		_watch_box.add_child(row)
		_watch_rows[s] = {"row": row, "name": n, "price": pr, "chg": ch}
	controls["watch"] = _watch_box
	var sep := ColorRect.new()
	sep.color = UI.BORDER
	sep.custom_minimum_size = Vector2(176, 1)
	v.add_child(sep)
	# 手数
	var hl2 := UI.hbox(2)
	hl2.add_child(_fixed(UI.label("手数", UI.DIM), 26))
	var bm := _small_btn("-", func(): _change_lots(-1))
	hl2.add_child(bm)
	_lots_lbl = UI.label("1.0", UI.YELLOW)
	_lots_lbl.custom_minimum_size.x = 40
	_lots_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl2.add_child(_lots_lbl)
	hl2.add_child(_small_btn("+", func(): _change_lots(1)))
	hl2.add_child(_small_btn("½", func(): _set_lots_frac(0.5)))
	hl2.add_child(_small_btn("MAX", func(): _set_lots_frac(1.0)))
	v.add_child(hl2)
	controls["lots"] = hl2
	# SL / TP
	var hs := UI.hbox(2)
	hs.add_child(_fixed(UI.label("止损", Color("ff9f43")), 26))
	hs.add_child(_small_btn("-", func(): _change_pips("sl", -1)))
	_sl_lbl = UI.label("无", UI.TEXT)
	_sl_lbl.custom_minimum_size.x = 56
	_sl_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hs.add_child(_sl_lbl)
	hs.add_child(_small_btn("+", func(): _change_pips("sl", 1)))
	_trail_btn = _small_btn("追", func(): _toggle_trail())
	_trail_btn.tooltip_text = "追踪止损（需要手法「追踪止损」）"
	hs.add_child(_trail_btn)
	v.add_child(hs)
	controls["sl"] = hs
	var ht := UI.hbox(2)
	ht.add_child(_fixed(UI.label("止盈", UI.CYAN), 26))
	ht.add_child(_small_btn("-", func(): _change_pips("tp", -1)))
	_tp_lbl = UI.label("无", UI.TEXT)
	_tp_lbl.custom_minimum_size.x = 56
	_tp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ht.add_child(_tp_lbl)
	ht.add_child(_small_btn("+", func(): _change_pips("tp", 1)))
	v.add_child(ht)
	controls["tp"] = ht
	# 买卖
	var hb := UI.hbox(3)
	_sell_btn = UI.button("卖\n", _do_sell)
	_buy_btn = UI.button("买\n", _do_buy)
	for b in [_sell_btn, _buy_btn]:
		b.custom_minimum_size = Vector2(86, 30)
	_sell_btn.add_theme_stylebox_override("normal", UI.box(Color("163a2e"), UI.DOWN, 1, 2))
	_sell_btn.add_theme_stylebox_override("hover", UI.box(Color("1d5040"), UI.DOWN, 1, 2))
	_buy_btn.add_theme_stylebox_override("normal", UI.box(Color("4a1a28"), UI.UP, 1, 2))
	_buy_btn.add_theme_stylebox_override("hover", UI.box(Color("652235"), UI.UP, 1, 2))
	hb.add_child(_sell_btn)
	hb.add_child(_buy_btn)
	v.add_child(hb)
	controls["sell"] = _sell_btn
	controls["buy"] = _buy_btn
	var hc := UI.hbox(3)
	var close_sym := UI.button("平此品种", _close_symbol)
	close_sym.custom_minimum_size.x = 86
	var close_all := UI.button("全部平仓", _close_all)
	close_all.custom_minimum_size.x = 86
	hc.add_child(close_sym)
	hc.add_child(close_all)
	v.add_child(hc)
	controls["close_all"] = close_all
	controls["close_symbol"] = close_sym
	_acct_lbl = UI.rich()
	_acct_lbl.custom_minimum_size = Vector2(176, 38)
	v.add_child(_acct_lbl)
	controls["account"] = _acct_lbl

func _fixed(c: Control, w: int) -> Control:
	c.custom_minimum_size.x = w
	return c

func _small_btn(t: String, cb: Callable) -> Button:
	var b := UI.button(t, cb)
	b.custom_minimum_size = Vector2(14 if t.length() <= 1 else 26, 12)
	b.add_theme_stylebox_override("normal", UI.box(UI.PANEL2, UI.BORDER, 1, 0))
	b.add_theme_stylebox_override("hover", UI.box(Color("3d3060"), UI.BORDER_HI, 1, 0))
	b.add_theme_stylebox_override("pressed", UI.box(Color("4a3a75"), UI.PINK, 1, 0))
	return b

func _build_bottom() -> void:
	_portrait_frame = UI.panel(Color("1d1530"), UI.PINK)
	_portrait_frame.position = Vector2(0, 239)
	_portrait_frame.size = Vector2(72, 107)
	_portrait_frame.add_theme_stylebox_override("panel", UI.box(Color("1d1530"), UI.PINK, 1, 1))
	add_child(_portrait_frame)
	var pv := UI.vbox(1)
	_portrait_frame.add_child(pv)
	_portrait = TextureRect.new()
	_portrait.custom_minimum_size = Vector2(64, 64)
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	pv.add_child(_portrait)
	var nm := UI.label("久留美", UI.PINK)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pv.add_child(nm)
	_hint_lbl = UI.label("", UI.DIM)
	_hint_lbl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_hint_lbl.custom_minimum_size.x = 68
	pv.add_child(_hint_lbl)
	var tp := UI.panel(UI.PANEL, UI.BORDER)
	tp.position = Vector2(73, 239)
	tp.size = Vector2(382, 107)
	tp.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 1, 1))
	add_child(tp)
	var tv := UI.vbox(1)
	tp.add_child(tv)
	_tabbar = TabBar.new()
	_tabbar.focus_mode = Control.FOCUS_NONE
	for t in ["持仓", "经济日历", "新闻", "FX民", "成交"]:
		_tabbar.add_tab(t)
	_tabbar.tab_changed.connect(func(_i): _tab_dirty = true; _refresh_tab())
	tv.add_child(_tabbar)
	controls["tabs"] = _tabbar
	_tab_scroll = ScrollContainer.new()
	_tab_scroll.custom_minimum_size = Vector2(378, 86)
	_tab_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tv.add_child(_tab_scroll)
	_tab_body = UI.vbox(0)
	_tab_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tab_scroll.add_child(_tab_body)

func _build_ticker() -> void:
	var p := UI.panel(Color("0e0a18"), UI.BORDER)
	p.position = Vector2(0, 347)
	p.size = Vector2(640, 13)
	p.add_theme_stylebox_override("panel", UI.box(Color("0e0a18"), UI.BORDER, 1, 0))
	add_child(p)
	_ticker_clip = Control.new()
	_ticker_clip.clip_contents = true
	_ticker_clip.position = Vector2(0, 347)
	_ticker_clip.size = Vector2(640, 13)
	add_child(_ticker_clip)
	_ticker = UI.label("", UI.YELLOW)
	_ticker.position = Vector2(640, 0)
	_ticker_clip.add_child(_ticker)

func _build_bubble() -> void:
	_bubble = PanelContainer.new()
	_bubble.add_theme_stylebox_override("panel", UI.box(Color("fff4fa"), UI.PINK, 1, 3))
	_bubble.position = Vector2(4, 196)
	_bubble.custom_minimum_size = Vector2(40, 16)
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble_lbl = UI.label("", Color("3a1030"))
	_bubble.add_child(_bubble_lbl)
	_bubble.visible = false
	_popup_layer.add_child(_bubble)

func _build_breaking() -> void:
	_breaking = PanelContainer.new()
	_breaking.add_theme_stylebox_override("panel", UI.box(Color("2a0f1c"), UI.UP, 2, 5))
	_breaking.mouse_filter = Control.MOUSE_FILTER_STOP
	_breaking.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _breaking.visible = false)
	_breaking.visible = false
	_popup_layer.add_child(_breaking)

func _build_objective() -> void:
	_objective = PanelContainer.new()
	_objective.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.1, 0.85), UI.YELLOW, 1, 3))
	_objective.position = Vector2(4, 32)
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective_lbl = UI.rich()
	_objective_lbl.custom_minimum_size = Vector2(200, 0)
	_objective_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_objective.add_child(_objective_lbl)
	_objective.visible = false
	_popup_layer.add_child(_objective)

# ================================================================ 信号

func _connect() -> void:
	session.ticked.connect(_on_ticked)
	session.alert.connect(_on_alert)
	session.finished.connect(_on_finished)
	session.script_pause.connect(_on_script_pause)
	session.script_dialog.connect(_on_script_dialog)
	session.events.news_posted.connect(_on_news)
	session.events.sns_posted.connect(func(_i): if _tabbar.current_tab == 3: _tab_dirty = true)
	session.events.calendar_updated.connect(func(): _tab_dirty = true)
	session.kurumi.said.connect(_on_said)
	session.kurumi.impulse.connect(_on_impulse)
	session.kurumi.tilt_changed.connect(func(on): _portrait_frame.add_theme_stylebox_override("panel", UI.box(Color("2a0f1c") if on else Color("1d1530"), UI.UP if on else UI.PINK, 1, 1)))
	session.account.opened.connect(func(_p): _tab_dirty = true; Sfx.play("open"); objective_event.emit("open", {"pos": _p}))
	session.account.closed.connect(_on_pos_closed)
	session.market.peg_broken.connect(func(_s): chart.shake(6.0); chart.flash(UI.UP))
	chart.sl_tp_dragged.connect(_on_line_dragged)
	chart.price_clicked.connect(_on_price_picked)

func _on_ticked() -> void:
	_refresh_all()

func _on_pos_closed(pos: Account.Position, pnl: float, reason: String) -> void:
	_tab_dirty = true
	Sfx.play("win" if pnl >= 0.0 else "lose")
	objective_event.emit("close", {"pos": pos, "pnl": pnl, "reason": reason})

func _on_alert(kind: String, text: String) -> void:
	match kind:
		"margin":
			chart.flash(UI.ORANGE)
			Sfx.play("alarm")
			if Save.setting("auto_pause_margin", true):
				_set_speed(0)
		"stopout":
			chart.flash(UI.UP)
			chart.shake(5.0)
			Sfx.play("crash")
			_set_speed(0)
		"sl":
			chart.flash(UI.ORANGE)
		"tp":
			chart.flash(UI.CYAN)
	_toast(text, UI.ORANGE if kind != "tp" else UI.CYAN)

func _on_news(item: Dictionary) -> void:
	_ticker_push(item.title)
	var col := UI.YELLOW
	match item.kind:
		"disaster": col = UI.UP
		"indicator": col = UI.CYAN
		"rumor": col = Color("9b86d6")
		"cb": col = UI.ORANGE
	chart.event_marks.append({"tick": session.market.tick, "icon": item.get("icon", "paper"), "color": col, "symbol": ""})
	if chart.event_marks.size() > 60:
		chart.event_marks.pop_front()
	_tab_dirty = true
	var sev := int(item.get("severity", 1))
	if sev >= 3 or item.kind in ["disaster", "cb"]:
		_show_breaking(item)
		chart.shake(3.0)
		Sfx.play("news")
		if Save.setting("auto_pause_news", true):
			_set_speed(0)

func _on_said(text: String, face: String) -> void:
	_bubble_lbl.text = text
	_bubble.reset_size()
	_bubble.visible = true
	_bubble_t = 3.5
	_set_face(face)

func _on_script_pause(text: String) -> void:
	_set_speed(0)
	if text != "":
		show_message(text)

func _on_script_dialog(lines: Array) -> void:
	_set_speed(0)
	var dlg := DialogueBox.new()
	dlg.lines = lines
	dlg.finished.connect(func(): _modal_open = false)
	_modal_open = true
	_popup_layer.add_child(dlg)

func _on_finished(result: Dictionary) -> void:
	finished = true
	_set_speed(0)
	if auto_close_on_finish:
		session.close_out()
		result.equity = session.account.equity()
		result.balance = session.account.balance
		result.debt = session.account.debt
	session_done.emit(result)

func _on_line_dragged(pos_id: int, which: String, price: float) -> void:
	for p in session.account.positions:
		if p.id == pos_id:
			if which == "sl":
				p.sl = price
			else:
				p.tp = price
			objective_event.emit("set_" + which, {"pos": p})
			chart.queue_redraw()
			_tab_dirty = true

func _on_price_picked(price: float) -> void:
	var mode := chart.pick_mode
	chart.pick_mode = ""
	var ins := session.market.get_ins(selected)
	var d := absf(price - ins.mid) / ins.pip
	if mode == "sl":
		sl_pips = roundf(d)
	else:
		tp_pips = roundf(d)
	_refresh_order()

# ================================================================ 输入

func _process(delta: float) -> void:
	if _bubble_t > 0.0:
		_bubble_t -= delta
		if _bubble_t <= 0.0:
			_bubble.visible = false
	if _breaking_t > 0.0:
		_breaking_t -= delta
		if _breaking_t <= 0.0:
			_breaking.visible = false
	# 新闻条滚动
	if _ticker.text != "":
		_ticker_x -= delta * 40.0
		if _ticker_x < -_ticker.size.x:
			_ticker_x = 640.0
		_ticker.position.x = floorf(_ticker_x)
	if finished or _modal_open or speed == 0:
		return
	_acc += delta * SPEEDS[speed]
	var n := 0
	while _acc >= 1.0 and n < 60:
		_acc -= 1.0
		n += 1
		_pre_tick_checks()
		if speed == 0:
			_acc = 0.0
			break
		session.advance()
		if session.done:
			break

func _pre_tick_checks() -> void:
	# 指标发布前自动暂停
	if Save.setting("auto_pause_indicator", true):
		for c in session.events.upcoming(1):
			if int(c.stars) >= 2 and c.tick == session.market.tick and not c.get("_paused", false):
				c["_paused"] = true
				_set_speed(0)
				_toast("指标即将发布：%s" % c.name, UI.CYAN)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _modal_open:
		return
	match event.keycode:
		KEY_SPACE:
			_set_speed(0 if speed > 0 else maxi(1, int(Save.setting("speed", 1))))
		KEY_1: _set_speed(1)
		KEY_2: _set_speed(2)
		KEY_3: _set_speed(3)
		KEY_4: _set_speed(4)
		KEY_B: _do_buy()
		KEY_S: _do_sell()
		KEY_C: _close_all()
		KEY_TAB:
			var i := session.symbols.find(selected)
			_select_symbol(session.symbols[(i + 1) % session.symbols.size()])
		_: return
	get_viewport().set_input_as_handled()

func _set_speed(i: int) -> void:
	if locked.get("speed", false) and i > 0 and hold_for_objective:
		return
	speed = i
	if i > 0:
		Save.data.settings.speed = i
	for k in _speed_btns.size():
		_speed_btns[k].add_theme_color_override("font_color", UI.YELLOW if k == i else UI.TEXT)

func _set_tf(i: int) -> void:
	chart.tf = TFS[i][0]
	chart.scroll = 0
	for k in _tf_btns.size():
		_tf_btns[k].add_theme_color_override("font_color", UI.YELLOW if k == i else UI.DIM)
	chart.queue_redraw()

func _select_symbol(s: String) -> void:
	selected = s
	chart.symbol = s
	chart.scroll = 0
	chart.event_marks = chart.event_marks
	_refresh_all()

func _change_lots(dir: int) -> void:
	var steps := [0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 3.0, 5.0, 10.0, 20.0, 30.0, 50.0, 100.0, 200.0, 300.0, 500.0]
	var idx := 0
	for i in steps.size():
		if steps[i] <= lots + 0.0001:
			idx = i
	idx = clampi(idx + dir, 0, steps.size() - 1)
	lots = steps[idx]
	_refresh_order()

func _set_lots_frac(f: float) -> void:
	var m := session.account.max_lots(selected)
	lots = maxf(0.1, floorf(m * f * 10.0) / 10.0)
	_refresh_order()

func _pip_steps() -> Array:
	return [0.0, 5.0, 10.0, 15.0, 20.0, 30.0, 40.0, 50.0, 70.0, 100.0, 150.0, 200.0, 300.0, 500.0]

func _change_pips(which: String, dir: int) -> void:
	var cur := sl_pips if which == "sl" else tp_pips
	var steps := _pip_steps()
	var idx := 0
	for i in steps.size():
		if steps[i] <= cur + 0.001:
			idx = i
	idx = clampi(idx + dir, 0, steps.size() - 1)
	if which == "sl":
		sl_pips = steps[idx]
	else:
		tp_pips = steps[idx]
	objective_event.emit("pips_" + which, {"value": steps[idx]})
	_refresh_order()

func _toggle_trail() -> void:
	if not session.mods.flag("trailing"):
		_toast("需要手法「追踪止损」", UI.DIM)
		return
	trail = not trail
	_refresh_order()

func _order_prices(side: int) -> Vector2:
	var ins := session.market.get_ins(selected)
	var px := session.account.ask(ins) if side > 0 else session.account.bid(ins)
	var sl := 0.0
	var tp := 0.0
	if sl_pips > 0.0:
		sl = px - side * sl_pips * ins.pip
	if tp_pips > 0.0:
		tp = px + side * tp_pips * ins.pip
	return Vector2(sl, tp)

func _do_buy() -> void:
	_place(1)

func _do_sell() -> void:
	_place(-1)

func _place(side: int) -> void:
	if locked.get("buy" if side > 0 else "sell", false):
		_toast("现在还不能这样做", UI.DIM)
		return
	var st := _order_prices(side)
	var r = session.buy(selected, lots, st.x, st.y) if side > 0 else session.sell(selected, lots, st.x, st.y)
	if r is String:
		_toast(r, UI.UP)
		Sfx.play("error")
	elif trail and sl_pips > 0.0:
		var ins := session.market.get_ins(selected)
		(r as Account.Position).trail = sl_pips * ins.pip
	_refresh_all()

func _close_all() -> void:
	if locked.get("close", false):
		_toast("现在还不能平仓", UI.DIM)
		return
	session.account.close_all("手动")
	_refresh_all()

func _close_symbol() -> void:
	if locked.get("close", false):
		_toast("现在还不能平仓", UI.DIM)
		return
	for p in session.account.positions.duplicate():
		if p.symbol == selected:
			session.account.close_position(p)
	_refresh_all()

func close_pos(p: Account.Position) -> void:
	if locked.get("close", false):
		_toast("现在还不能平仓", UI.DIM)
		return
	session.account.close_position(p)
	_refresh_all()

# ================================================================ 刷新

func _refresh_all() -> void:
	var m := session.market
	var acc := session.account
	_top_date.text = session.now_text()
	var hr := m.hour()
	var sess := "东京"
	if hr >= 16 and hr < 21:
		sess = "伦敦"
	elif hr >= 21 or hr < 2:
		sess = "伦敦+纽约"
	elif hr >= 2 and hr < 7:
		sess = "纽约"
	_top_session.text = sess
	var eq := acc.equity()
	_top_equity.text = "净值 " + GameDate.yen(eq)
	_top_equity.add_theme_color_override("font_color", UI.TEXT if acc.debt <= 0.0 else UI.UP)
	_mental_bar.max_value = session.kurumi.mental_max()
	_mental_bar.value = session.kurumi.mental
	_mental_bar.add_theme_stylebox_override("fill", UI.box(UI.UP if session.kurumi.tilt else UI.PINK, UI.PINK, 0, 0))
	_mental_lbl.text = str(int(session.kurumi.mental))
	var goal: Dictionary = session.cfg.get("goal", {})
	var days_left := ceili(float(session.ticks_left()) / MarketSim.TICKS_PER_DAY)
	var gt := "剩 %d 天" % days_left
	if goal.has("equity"):
		gt = "目标 %s  %s" % [GameDate.yen(float(goal.equity)), gt]
	if session.cfg.has("goal_text"):
		gt = "%s  %s" % [session.cfg.goal_text, gt]
	_top_goal.text = gt
	# 自选
	for s in _watch_rows:
		var ins := m.get_ins(s)
		var r: Dictionary = _watch_rows[s]
		var bid := acc.bid(ins)
		r.price.text = m.format_price(ins, bid)
		var n := ins.c.size()
		var ref := ins.c[maxi(0, n - MarketSim.TICKS_PER_DAY)] if n > 0 else bid
		var chg := (ins.mid / ref - 1.0) * 100.0
		r.chg.text = "%+.2f%%" % chg
		r.chg.add_theme_color_override("font_color", UI.up_down(chg))
		r.name.add_theme_color_override("font_color", UI.YELLOW if s == selected else UI.TEXT)
	_refresh_order()
	# 账户
	var ml := acc.margin_level()
	var ml_s := "—" if ml == INF else "%.0f%%" % ml
	var ml_col := UI.TEXT
	if ml != INF and ml < float(acc.broker.margin_call):
		ml_col = UI.UP
	var t := "余额 %s  含み [color=#%s]%s[/color]\n" % [GameDate.yen(acc.balance), UI.hex(UI.up_down(acc.floating_total())), GameDate.yen(acc.floating_total(), true)]
	t += "维持率 [color=#%s]%s[/color]（强平 %.0f%%）\n" % [UI.hex(ml_col), ml_s, acc.stopout_level()]
	t += "[color=#%s]%s %d倍[/color]" % [UI.hex(UI.DIM), acc.broker.get("name", ""), int(acc.leverage())]
	if acc.credit > 0.0:
		t += "  赠金%s" % GameDate.yen(acc.credit)
	if acc.debt > 0.0:
		t += "\n[color=#%s]不足金 %s[/color]" % [UI.hex(UI.UP), GameDate.yen(acc.debt)]
	_acct_lbl.text = t
	_set_face(session.kurumi.face)
	if _tab_dirty or (_tabbar.current_tab == 0 and Engine.get_process_frames() % 2 == 0):
		_refresh_tab()
	chart.preview_lines.clear()
	var st := _order_prices(1)
	var ins2 := m.get_ins(selected)
	if sl_pips > 0.0:
		chart.preview_lines.append({"price": st.x, "color": Color(1, 0.62, 0.26, 0.4), "label": "-%d" % int(sl_pips)})
		chart.preview_lines.append({"price": acc.bid(ins2) + sl_pips * ins2.pip, "color": Color(1, 0.62, 0.26, 0.25), "label": ""})
	chart.queue_redraw()

func _refresh_order() -> void:
	var m := session.market
	var ins := m.get_ins(selected)
	var acc := session.account
	_lots_lbl.text = ("%.1f" % lots) + "枚"
	_sl_lbl.text = "无" if sl_pips <= 0.0 else "%d pips" % int(sl_pips)
	_tp_lbl.text = "无" if tp_pips <= 0.0 else "%d pips" % int(tp_pips)
	_trail_btn.add_theme_color_override("font_color", UI.YELLOW if trail else (UI.TEXT if session.mods.flag("trailing") else UI.MUTED))
	_sell_btn.text = "卖 %s\n%s" % [selected, m.format_price(ins, acc.bid(ins))]
	_buy_btn.text = "买 %s\n%s" % [selected, m.format_price(ins, acc.ask(ins))]
	var need := acc.margin_for(selected, lots)
	var risk := ""
	if sl_pips > 0.0:
		var loss := sl_pips * ins.pip * lots * ins.contract * m.jpy_value(ins.quote)
		risk = " 止损亏%s" % GameDate.yen(loss)
	_hint_lbl.text = ""
	_buy_btn.tooltip_text = "证拠金 %s%s" % [GameDate.yen(need), risk]
	_sell_btn.tooltip_text = _buy_btn.tooltip_text

func _refresh_tab() -> void:
	_tab_dirty = false
	for c in _tab_body.get_children():
		c.queue_free()
	match _tabbar.current_tab:
		0: _tab_positions()
		1: _tab_calendar()
		2: _tab_news()
		3: _tab_sns()
		4: _tab_history()

func _row(text: String, col: Color = UI.TEXT) -> Label:
	var l := UI.label(text, col)
	l.clip_text = true
	l.custom_minimum_size = Vector2(370, 12)
	_tab_body.add_child(l)
	return l

func _tab_positions() -> void:
	var acc := session.account
	var m := session.market
	if acc.positions.is_empty():
		_row("没有持仓。选好品种和手数，按「买」或「卖」开始交易。", UI.DIM)
		return
	for p in acc.positions:
		var ins := m.get_ins(p.symbol)
		var h := UI.hbox(3)
		var pnl := acc.floating(p)
		var txt := "%s %s%.1f @%s 现%s" % [p.symbol, p.dir_name(), p.lots, m.format_price(ins, p.entry), m.format_price(ins, acc.exit_price(p))]
		var l := UI.label(txt, UI.UP if p.side > 0 else UI.DOWN)
		l.custom_minimum_size.x = 200
		l.clip_text = true
		h.add_child(l)
		var pl := UI.label(GameDate.yen(pnl, true), UI.up_down(pnl))
		pl.custom_minimum_size.x = 64
		h.add_child(pl)
		var sltp := "SL%s TP%s" % ["—" if p.sl <= 0.0 else m.format_price(ins, p.sl), "—" if p.tp <= 0.0 else m.format_price(ins, p.tp)]
		var sl := UI.label(sltp, UI.DIM)
		sl.custom_minimum_size.x = 76
		sl.clip_text = true
		h.add_child(sl)
		var b := _small_btn("平", close_pos.bind(p))
		h.add_child(b)
		_tab_body.add_child(h)

func _tab_calendar() -> void:
	var ev := session.events
	var any := false
	var horizon := int(session.mods.get_v("calendar_days") * MarketSim.TICKS_PER_DAY) + MarketSim.TICKS_PER_DAY
	for c in ev.calendar:
		if not c.released and c.tick - session.market.tick > horizon:
			continue
		if c.released and session.market.tick - c.tick > MarketSim.TICKS_PER_DAY:
			continue
		any = true
		var d := session.date_of_day(int(c.day))
		var stars := "★".repeat(int(c.stars))
		var fmt: String = c.fmt
		var fc := fmt % float(c.forecast)
		var t := "%s %02d:%02d %s %s 预测%s" % [GameDate.fmt_md(d + (86400 if int(c.hour) < 7 else 0)), int(c.hour), int(c.minute), stars, c.name, fc]
		var col := UI.TEXT
		if c.released:
			t += " → 实际%s" % (fmt % float(c.actual))
			col = UI.MUTED
		elif session.mods.get_v("forecast_acc") > 0.0:
			t += "  预感:%s" % ("上振" if int(c.hint) > 0 else "下振")
			col = UI.CYAN
		_row(t, col)
	if not any:
		_row("近期没有重要经济指标。", UI.DIM)

func _tab_news() -> void:
	var log_: Array = session.events.news_log
	if log_.is_empty():
		_row("还没有新闻。", UI.DIM)
	for i in range(log_.size() - 1, maxi(-1, log_.size() - 40), -1):
		var it: Dictionary = log_[i]
		var col := UI.TEXT
		if it.kind == "rumor":
			col = Color("c9b6ff")
		elif it.kind == "denial":
			col = UI.DIM
		elif it.kind == "disaster":
			col = UI.UP
		var clk := _tick_clock(int(it.tick))
		_row("%s %s" % [clk, it.title], col)

func _tab_sns() -> void:
	var log_: Array = session.events.sns_log
	for i in range(log_.size() - 1, maxi(-1, log_.size() - 30), -1):
		var it: Dictionary = log_[i]
		_row("%s %s：%s" % [_tick_clock(int(it.tick)), it.who, it.text], Color("ffb3d1") if it.who == "@あふぃちゃん" else UI.TEXT)
	if log_.is_empty():
		_row("时间线很安静。", UI.DIM)

func _tab_history() -> void:
	var h: Array = session.account.history
	if h.is_empty():
		_row("还没有成交记录。", UI.DIM)
	for i in range(h.size() - 1, maxi(-1, h.size() - 30), -1):
		var it: Dictionary = h[i]
		var ins := session.market.get_ins(it.symbol)
		_row("%s %s%.1f %s→%s %s [%s]" % [it.symbol, "买" if it.side > 0 else "卖", it.lots, session.market.format_price(ins, it.entry), session.market.format_price(ins, it.exit), GameDate.yen(it.pnl, true), it.reason], UI.up_down(it.pnl))

func _tick_clock(t: int) -> String:
	var mins := MarketSim.DAY_START_HOUR * 60 + (t % MarketSim.TICKS_PER_DAY) * 15
	return "%02d:%02d" % [(mins / 60) % 24, mins % 60]

func _set_face(face: String) -> void:
	var tex := Portraits.small("kurumi", face)
	if _portrait.texture != tex:
		_portrait.texture = tex

# ================================================================ 弹窗

func _ticker_push(title: String) -> void:
	var items: Array = []
	var log_: Array = session.events.news_log
	for i in range(log_.size() - 1, maxi(-1, log_.size() - 4), -1):
		items.append(log_[i].title)
	_ticker.text = "　◆　".join(items)
	_ticker.reset_size()
	if _ticker_x < 0.0 or _ticker_x > 640.0:
		_ticker_x = 640.0

func _show_breaking(item: Dictionary) -> void:
	for c in _breaking.get_children():
		c.queue_free()
	var h := UI.hbox(6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ic := PixelIcons.texture_rect(item.get("icon", "paper"), 3)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(ic)
	var v := UI.vbox(2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tag := "【速報】" if item.kind != "rumor" else "【未確認】"
	v.add_child(UI.label(tag, UI.UP))
	var tl := UI.label(item.title, UI.WHITE)
	tl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	tl.custom_minimum_size.x = 300
	v.add_child(tl)
	if String(item.get("body", "")) != "":
		var bl := UI.label(item.body, UI.DIM)
		bl.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		bl.custom_minimum_size.x = 300
		v.add_child(bl)
	h.add_child(v)
	_breaking.add_child(h)
	_breaking.reset_size()
	_breaking.position = Vector2(floorf((455 - 340) / 2.0), 70)
	_breaking.visible = true
	_breaking_t = 4.0

func _toast(text: String, col: Color) -> void:
	var l := UI.label(text, col)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.1, 0.92), col, 1, 3))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_popup_layer.add_child(p)
	p.reset_size()
	p.position = Vector2(floorf((455 - p.size.x) / 2.0), 186)
	var tw := create_tween()
	tw.tween_interval(1.8)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

## 剧情/教学用：显示一段说明并暂停，点击继续
func show_message(text: String, on_close: Callable = Callable()) -> void:
	_set_speed(0)
	_modal_open = true
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(dim)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color("201838"), UI.YELLOW, 1, 6))
	var v := UI.vbox(6)
	var r := UI.rich(text)
	r.custom_minimum_size = Vector2(360, 0)
	v.add_child(r)
	var ok := UI.button("明白了", func():
		dim.queue_free()
		p.queue_free()
		_modal_open = false
		if on_close.is_valid():
			on_close.call()
	)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_END
	v.add_child(ok)
	p.add_child(v)
	_popup_layer.add_child(p)
	p.reset_size()
	p.position = (Vector2(640, 360) - p.size) / 2.0
	p.position = p.position.floor()

func set_objective(bb: String) -> void:
	if bb == "":
		_objective.visible = false
		return
	_objective_lbl.text = bb
	_objective.visible = true
	_objective.reset_size()

func lock(names: Array, on := true) -> void:
	for n in names:
		locked[n] = on
		if controls.has(n) and controls[n] is Control:
			controls[n].modulate = Color(1, 1, 1, 0.35) if on else Color(1, 1, 1, 1)

func highlight(name_: String, on := true) -> void:
	if not controls.has(name_):
		return
	var c: Control = controls[name_]
	if on:
		var tw := c.create_tween().set_loops(6)
		tw.tween_property(c, "modulate", Color(1.6, 1.4, 0.6), 0.25)
		tw.tween_property(c, "modulate", Color(1, 1, 1), 0.25)

func _on_impulse(kind: String) -> void:
	if finished:
		return
	_set_speed(0)
	_modal_open = true
	var acc := session.account
	var worst: Account.Position = null
	for p in acc.positions:
		if worst == null or acc.floating(p) < acc.floating(worst):
			worst = p
	var text := ""
	var act_label := ""
	if kind == "nanpin" and worst != null:
		text = "【衝動】%s 的含み損越来越大……\n“再加仓的话平均价格就会变好，反弹时就能一口气取回来！”" % worst.symbol
		act_label = "全力ナンピン！"
	else:
		text = "【衝動】“什么都不做的话，2000万永远拿不回来……”\n手指在买入按钮上发抖。"
		act_label = "满仓买入！"
	var dim := ColorRect.new()
	dim.color = Color(0.3, 0, 0.05, 0.4)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_popup_layer.add_child(dim)
	var p2 := PanelContainer.new()
	p2.add_theme_stylebox_override("panel", UI.box(Color("2a0f1c"), UI.UP, 2, 6))
	var v := UI.vbox(6)
	var r := UI.rich("[color=#ff9fb5]%s[/color]" % text)
	r.custom_minimum_size = Vector2(340, 0)
	v.add_child(r)
	v.add_child(UI.label("（暴走中：屈服于冲动 メンタル+10；忍住 メンタル-4）", UI.DIM))
	var h := UI.hbox(8)
	var close := func():
		dim.queue_free()
		p2.queue_free()
		_modal_open = false
	h.add_child(UI.button(act_label, func():
		close.call()
		session.kurumi.change(10.0)
		if worst != null and kind == "nanpin":
			var ml := acc.max_lots(worst.symbol)
			if ml >= 0.1:
				acc.open_position(worst.symbol, worst.side, ml)
		else:
			var ml2 := acc.max_lots(selected)
			if ml2 >= 0.1:
				acc.open_position(selected, 1, ml2)
		_refresh_all()
	))
	h.add_child(UI.button("深呼吸……忍住", func():
		close.call()
		session.kurumi.change(-4.0)
	))
	v.add_child(h)
	p2.add_child(v)
	_popup_layer.add_child(p2)
	p2.reset_size()
	p2.position = ((Vector2(640, 360) - p2.size) / 2.0).floor()
	Sfx.play("alarm")

func _exit_tree() -> void:
	if session:
		session.dispose()
