class_name ChartView
extends Control
## 像素 K 线图：蜡烛、指标、持仓/止损/止盈线、事件标记、公允价值、止损簇、十字光标。
## 缩放：滚轮 / 双指捏合；平移：右键拖动，或单指（左键）拖动空白处（手机没有右键）。
## 拖动持仓的 SL/TP 线可以直接改单。

signal sl_tp_dragged(pos_id: int, which: String, price: float)
signal price_clicked(price: float)

const AXIS_W := 44
const TIME_H := 11
const RSI_H := 30

var session: TradeSession
var symbol := "USDJPY"
var tf := 4 # 每根蜡烛包含的 tick 数
var candle_w := 4
var scroll := 0 # 向左平移的蜡烛数（0 = 跟随最新）
var event_marks: Array[Dictionary] = [] # {tick, icon, color, symbol}
var preview_lines: Array[Dictionary] = [] # {price, color, label}
var pick_mode := "" # "sl"/"tp" 时点击设定价格
var _mouse := Vector2(-1, -1)
var _drag_pan := false
var _drag_start := Vector2.ZERO
var _drag_scroll := 0
var _drag_line := {} # {pos_id, which}
var _pmin := 0.0
var _pmax := 1.0
var _plot := Rect2()
var _shake := 0.0
var _flash := 0.0
var _flash_color := Color.RED
# 触屏手势：index -> 位置。双指 = 捏合缩放 + 拖动平移；单指靠触摸模拟的鼠标事件。
var _touches := {}
var _multitouch := false
var _pinch_dist := 0.0
var _pinch_accum := 1.0
var _pinch_candle_w := 4
var _pinch_mid := Vector2.ZERO

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true

func shake(amount := 3.0) -> void:
	if Save.setting("screen_shake", true):
		_shake = maxf(_shake, amount)

func flash(c: Color) -> void:
	_flash = 1.0
	_flash_color = c

func _process(delta: float) -> void:
	if _shake > 0.0 or _flash > 0.0:
		_shake = maxf(0.0, _shake - delta * 12.0)
		_flash = maxf(0.0, _flash - delta * 2.0)
		queue_redraw()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch_pressed(event)
		return
	if event is InputEventScreenDrag:
		_touch_moved(event)
		return
	if event is InputEventMagnifyGesture:
		_set_candle_w(int(round(candle_w * event.factor)))
		return
	if _multitouch:
		return # 双指手势期间，忽略触摸模拟出来的鼠标事件
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _drag_pan:
			scroll = maxi(0, _drag_scroll + int((event.position.x - _drag_start.x) / candle_w))
		elif not _drag_line.is_empty():
			var p := _y_to_price(event.position.y)
			sl_tp_dragged.emit(_drag_line.pos_id, _drag_line.which, p)
		queue_redraw()
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_set_candle_w(candle_w + 1)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_set_candle_w(candle_w - 1)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_pan = event.pressed
			_drag_start = event.position
			_drag_scroll = scroll
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if pick_mode != "":
					price_clicked.emit(_y_to_price(event.position.y))
					return
				_drag_line = _line_at(event.position.y)
				if _drag_line.is_empty():
					# 空白处按下：拖动平移（手机上等价于右键拖动）
					_drag_pan = true
					_drag_start = event.position
					_drag_scroll = scroll
			else:
				_drag_line = {}
				_drag_pan = false

func _set_candle_w(w: int) -> void:
	var nw := clampi(w, 2, 10)
	if nw == candle_w:
		return
	candle_w = nw
	queue_redraw()

# ---------------------------------------------------------------- 触屏手势

func _touch_pressed(e: InputEventScreenTouch) -> void:
	if e.pressed:
		_touches[e.index] = e.position
		_mouse = e.position
		if _touches.size() >= 2:
			_begin_pinch()
	else:
		_touches.erase(e.index)
		if _touches.size() < 2:
			_pinch_dist = 0.0
		if _touches.is_empty():
			_multitouch = false
	queue_redraw()

func _touch_moved(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _touches.size() < 2:
		return
	var ks := _touches.keys()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	var gap := a.distance_to(b)
	var mid := (a + b) * 0.5
	if _pinch_dist <= 0.0:
		_begin_pinch()
		return
	# 捏合 = 缩放（以右端为锚点，和滚轮一致）
	_pinch_accum = clampf(_pinch_accum * (gap / maxf(1.0, _pinch_dist)), 0.25, 4.0)
	_set_candle_w(int(round(_pinch_candle_w * _pinch_accum)))
	# 双指整体移动 = 平移
	var dx := mid.x - _pinch_mid.x
	if absf(dx) >= 1.0:
		scroll = maxi(0, scroll + int(round(dx / float(candle_w))))
		_pinch_mid = mid
	_pinch_dist = gap
	_mouse = mid
	queue_redraw()

func _begin_pinch() -> void:
	var ks := _touches.keys()
	var a: Vector2 = _touches[ks[0]]
	var b: Vector2 = _touches[ks[1]]
	_pinch_dist = a.distance_to(b)
	_pinch_mid = (a + b) * 0.5
	_pinch_accum = 1.0
	_pinch_candle_w = candle_w
	_multitouch = true
	_drag_line = {}
	_drag_pan = false

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT:
		_mouse = Vector2(-1, -1)
		queue_redraw()

func _line_at(y: float) -> Dictionary:
	if session == null:
		return {}
	var tol := 6.0 if Game.touch else 3.0 # 手指比鼠标粗：触屏放宽命中范围
	for p in session.account.positions:
		if p.symbol != symbol:
			continue
		if p.sl > 0.0 and absf(_price_to_y(p.sl) - y) <= tol:
			return {"pos_id": p.id, "which": "sl"}
		if p.tp > 0.0 and absf(_price_to_y(p.tp) - y) <= tol:
			return {"pos_id": p.id, "which": "tp"}
	return {}

func _price_to_y(p: float) -> float:
	if _pmax <= _pmin:
		return _plot.position.y
	return _plot.position.y + (1.0 - (p - _pmin) / (_pmax - _pmin)) * _plot.size.y

func _y_to_price(y: float) -> float:
	return _pmin + (1.0 - (y - _plot.position.y) / _plot.size.y) * (_pmax - _pmin)

# ---------------------------------------------------------------- 绘制

func _draw() -> void:
	var font: Font = UI.font
	var off := Vector2.ZERO
	if _shake > 0.0:
		off = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake)).round()
	draw_set_transform(off)
	draw_rect(Rect2(Vector2.ZERO, size), Color("120d1d"))
	if session == null:
		return
	var m := session.market
	var ins := m.get_ins(symbol)
	if ins == null:
		return
	var mods := session.mods
	var show_rsi := mods.flag("ind_rsi")
	var h_plot := size.y - TIME_H - (RSI_H if show_rsi else 0)
	_plot = Rect2(1, 14, size.x - AXIS_W - 2, h_plot - 16)
	var n_vis := int(_plot.size.x / candle_w)
	var extra := 80 # 指标需要的额外历史
	var all := m.candles(symbol, tf, n_vis + extra + scroll)
	if all.is_empty():
		return
	var end_i := all.size() - scroll
	var start_i := maxi(0, end_i - n_vis)
	var vis := all.slice(start_i, end_i)
	if vis.is_empty():
		return
	# 价格范围
	_pmin = INF
	_pmax = -INF
	for c in vis:
		_pmin = minf(_pmin, c[2])
		_pmax = maxf(_pmax, c[1])
	var pad := (_pmax - _pmin) * 0.08 + ins.pip * 2.0
	_pmin -= pad
	_pmax += pad
	# 网格与价格轴
	var step := _nice_step((_pmax - _pmin) / 6.0)
	var g := ceilf(_pmin / step) * step
	while g < _pmax:
		var y := _price_to_y(g)
		draw_line(Vector2(_plot.position.x, y), Vector2(_plot.end.x, y), UI.GRID)
		draw_string(font, Vector2(_plot.end.x + 3, y + 4), m.format_price(ins, g), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)
		g += step
	# 止损簇（情报）
	if mods.flag("show_clusters"):
		var cl := m.stop_clusters(ins)
		for k in cl:
			var y2 := _price_to_y(cl[k])
			if y2 > _plot.position.y and y2 < _plot.end.y:
				draw_rect(Rect2(_plot.position.x, y2 - 2, _plot.size.x, 4), Color(1, 0.8, 0.2, 0.12))
				draw_string(font, Vector2(_plot.position.x + 2, y2 - 3), "止损簇", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.8, 0.2, 0.6))
	# 布林带 / 均线
	var closes: Array[float] = []
	for c in all.slice(0, end_i):
		closes.append(c[3])
	var base_x := _plot.position.x
	if mods.flag("ind_bb"):
		_draw_band(closes, vis.size(), 20, 2.0, base_x)
	if mods.flag("ind_ma"):
		_draw_ma(closes, vis.size(), 20, UI.YELLOW, base_x)
		_draw_ma(closes, vis.size(), 75, UI.CYAN, base_x)
	# 事件标记
	var first_tick: int = vis[0][4]
	for e in event_marks:
		if e.has("symbol") and e.symbol != "" and e.symbol != symbol:
			continue
		var idx := float(int(e.tick) - first_tick) / tf
		if idx < 0 or idx > vis.size():
			continue
		var x := base_x + idx * candle_w + candle_w * 0.5
		draw_line(Vector2(x, _plot.position.y), Vector2(x, _plot.end.y), Color(e.color, 0.35))
		var ic: Texture2D = PixelIcons.get_icon(e.get("icon", "paper"))
		if ic:
			draw_texture(ic, Vector2(x - 4, _plot.position.y - 1))
	# 蜡烛
	for i in vis.size():
		var c: Array = vis[i]
		var x0 := base_x + i * candle_w
		var up: bool = c[3] >= c[0]
		var col: Color = UI.UP if up else UI.DOWN
		var yo := _price_to_y(c[0])
		var yc := _price_to_y(c[3])
		var yh := _price_to_y(c[1])
		var yl := _price_to_y(c[2])
		var cx := floorf(x0 + (candle_w - 1) * 0.5)
		draw_line(Vector2(cx + 0.5, yh), Vector2(cx + 0.5, yl), col)
		var top := minf(yo, yc)
		var hgt := maxf(1.0, absf(yc - yo))
		var bw := maxi(1, candle_w - 1)
		draw_rect(Rect2(x0, floorf(top), bw, ceilf(hgt)), col)
	# 公允价值
	if mods.flag("show_fair"):
		var fy := _price_to_y(m.fair_price(ins))
		if fy > _plot.position.y and fy < _plot.end.y:
			_dashed(fy, Color(0.75, 0.55, 1.0, 0.8), 2, 3)
			draw_string(font, Vector2(_plot.end.x - 26, fy - 2), "公允", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.65, 1.0))
	# 预览线（下单前的 SL/TP）
	for pl in preview_lines:
		var py := _price_to_y(pl.price)
		_dashed(py, pl.color, 1, 3)
		_axis_tag(py, pl.get("label", ""), pl.color)
	# 持仓线
	for p in session.account.positions:
		if p.symbol != symbol:
			continue
		var col2: Color = UI.UP if p.side > 0 else UI.DOWN
		var ey := _price_to_y(p.entry)
		_dashed(ey, col2, 4, 2)
		var pnl := session.account.floating(p)
		_axis_tag(ey, "%s%.1f" % [p.dir_name(), p.lots], col2)
		draw_string(font, Vector2(_plot.position.x + 2, clampf(ey - 2, _plot.position.y + 10, _plot.end.y)), GameDate.yen(pnl, true), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.up_down(pnl))
		if p.sl > 0.0:
			var sy := _price_to_y(p.sl)
			_dashed(sy, Color("ff9f43"), 2, 2)
			_axis_tag(sy, "SL", Color("ff9f43"))
		if p.tp > 0.0:
			var ty := _price_to_y(p.tp)
			_dashed(ty, UI.CYAN, 2, 2)
			_axis_tag(ty, "TP", UI.CYAN)
	# 现价
	var bid := session.account.bid(ins)
	var by := _price_to_y(bid)
	draw_line(Vector2(_plot.position.x, by), Vector2(_plot.end.x, by), Color(1, 1, 1, 0.25))
	_axis_tag(by, m.format_price(ins, bid), Color("e8e0ff"), true)
	# 时间轴
	_draw_time_axis(vis, h_plot)
	# RSI
	if show_rsi:
		_draw_rsi(closes, vis.size(), Rect2(1, h_plot + TIME_H - 2, _plot.size.x, RSI_H - 2))
	# 顶部信息
	var head := "%s  %s" % [ins.name, m.format_price(ins, bid)]
	draw_string(font, Vector2(3, 11), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.TEXT)
	var spread_pips := session.account.spread_of(ins) / ins.pip
	var info := "点差 %.1f" % spread_pips
	if ins.halted:
		info += " 【报价停止】"
	var head_w := font.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	draw_string(font, Vector2(head_w + 12, 11), info, HORIZONTAL_ALIGNMENT_LEFT, 280 - head_w, 12, UI.DIM if spread_pips < ins.spread_pips * 3.0 else UI.ORANGE)
	# 左下角：情报类信息
	var info2 := ""
	if mods.flag("show_trend"):
		info2 += "趋势 %s/%s  " % [m.regime_name(ins.base), m.regime_name(ins.quote)]
	if mods.flag("show_sentiment"):
		info2 += "散户多 %d%%  " % int(ins.long_ratio * 100.0)
	var nxt := session.events.upcoming(48)
	if not nxt.is_empty():
		var c0: Dictionary = nxt[0]
		var left := int(c0.tick) - m.tick
		info2 += "下一指标 %02d:%02d %s%s（%d时%02d分后）" % [int(c0.hour), int(c0.minute), String(c0.name).split(" ")[0], "★".repeat(int(c0.stars)), left / 4, (left % 4) * 15]
	if info2 != "":
		var w2 := font.get_string_size(info2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_rect(Rect2(_plot.position.x, _plot.end.y - 12, w2 + 6, 12), Color(0.05, 0.03, 0.1, 0.7))
		draw_string(font, Vector2(_plot.position.x + 3, _plot.end.y - 2), info2, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.CYAN)
	# 十字光标
	if _mouse.x >= 0.0 and _plot.has_point(_mouse):
		draw_line(Vector2(_plot.position.x, _mouse.y), Vector2(_plot.end.x, _mouse.y), Color(1, 1, 1, 0.18))
		draw_line(Vector2(_mouse.x, _plot.position.y), Vector2(_mouse.x, _plot.end.y), Color(1, 1, 1, 0.18))
		_axis_tag(_mouse.y, m.format_price(ins, _y_to_price(_mouse.y)), UI.MUTED)
	if pick_mode != "":
		draw_string(font, Vector2(_plot.position.x + 4, _plot.end.y - 4), "点击图表设定 %s" % pick_mode.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.YELLOW)
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, 0.25 * _flash))
		draw_rect(Rect2(Vector2.ZERO, size), Color(_flash_color, _flash), false, 2.0)

func _dashed(y: float, col: Color, dash: int, gap: int) -> void:
	var x := _plot.position.x
	y = floorf(y) + 0.5
	if y < _plot.position.y or y > _plot.end.y:
		return
	while x < _plot.end.x:
		draw_line(Vector2(x, y), Vector2(minf(x + dash, _plot.end.x), y), col)
		x += dash + gap

func _axis_tag(y: float, text: String, col: Color, filled := false) -> void:
	y = clampf(y, _plot.position.y + 5, _plot.end.y - 5)
	var r := Rect2(_plot.end.x + 1, floorf(y) - 6, AXIS_W - 1, 12)
	if filled:
		draw_rect(r, col)
		draw_string(UI.font, Vector2(r.position.x + 2, r.position.y + 10), text, HORIZONTAL_ALIGNMENT_LEFT, AXIS_W - 3, 12, Color("120d1d"))
	else:
		draw_rect(r, Color("120d1d"))
		draw_rect(r, col, false, 1.0)
		draw_string(UI.font, Vector2(r.position.x + 2, r.position.y + 10), text, HORIZONTAL_ALIGNMENT_LEFT, AXIS_W - 3, 12, col)

func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var r := raw / mag
	if r < 1.5:
		return mag
	if r < 3.5:
		return 2.0 * mag
	if r < 7.5:
		return 5.0 * mag
	return 10.0 * mag

func _draw_ma(closes: Array[float], n_vis: int, period: int, col: Color, base_x: float) -> void:
	var n := closes.size()
	var prev := Vector2(-1, -1)
	for i in range(maxi(0, n - n_vis), n):
		if i < period - 1:
			continue
		var s := 0.0
		for k in range(i - period + 1, i + 1):
			s += closes[k]
		var v := s / period
		var x := base_x + (i - (n - n_vis)) * candle_w + candle_w * 0.5
		var pt := Vector2(x, _price_to_y(v))
		if prev.x >= 0.0:
			draw_line(prev, pt, Color(col, 0.85))
		prev = pt

func _draw_band(closes: Array[float], n_vis: int, period: int, k: float, base_x: float) -> void:
	var n := closes.size()
	var pu := Vector2(-1, -1)
	var pd := Vector2(-1, -1)
	var col := Color(0.6, 0.5, 1.0, 0.55)
	for i in range(maxi(0, n - n_vis), n):
		if i < period - 1:
			continue
		var s := 0.0
		for j in range(i - period + 1, i + 1):
			s += closes[j]
		var mean := s / period
		var v := 0.0
		for j in range(i - period + 1, i + 1):
			v += (closes[j] - mean) * (closes[j] - mean)
		var sd := sqrt(v / period)
		var x := base_x + (i - (n - n_vis)) * candle_w + candle_w * 0.5
		var a := Vector2(x, _price_to_y(mean + k * sd))
		var b := Vector2(x, _price_to_y(mean - k * sd))
		if pu.x >= 0.0:
			draw_line(pu, a, col)
			draw_line(pd, b, col)
		pu = a
		pd = b

func _draw_rsi(closes: Array[float], n_vis: int, r: Rect2) -> void:
	draw_rect(r, Color("150f22"))
	for lv in [30.0, 70.0]:
		var yy: float = r.position.y + (1.0 - lv / 100.0) * r.size.y
		draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), UI.GRID)
	var n := closes.size()
	var period := 14
	var prev := Vector2(-1, -1)
	for i in range(maxi(period, n - n_vis), n):
		var g := 0.0
		var l := 0.0
		for j in range(i - period + 1, i + 1):
			var d := closes[j] - closes[j - 1]
			if d > 0.0:
				g += d
			else:
				l -= d
		var rsi := 100.0 if l == 0.0 else 100.0 - 100.0 / (1.0 + g / l)
		var x := r.position.x + (i - (n - n_vis)) * candle_w + candle_w * 0.5
		var pt := Vector2(x, r.position.y + (1.0 - rsi / 100.0) * r.size.y)
		if prev.x >= 0.0:
			draw_line(prev, pt, UI.PINK)
		prev = pt
	draw_string(UI.font, Vector2(r.position.x + 2, r.position.y + 10), "RSI14", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)

func _draw_time_axis(vis: Array, y0: float) -> void:
	var m := session.market
	var label_every := 24 # tick
	match tf:
		1: label_every = 16
		4: label_every = 96
		16: label_every = 96 * 2
		96: label_every = 96 * 10
	var last_x := -100.0
	for i in vis.size():
		var t: int = vis[i][4]
		if t % label_every != 0:
			continue
		var x := _plot.position.x + i * candle_w
		if x - last_x < 40:
			continue
		last_x = x
		var d := t / MarketSim.TICKS_PER_DAY
		var unix := session.date_of_day(d)
		var txt := GameDate.fmt_md(unix)
		if tf == 1:
			var mins := MarketSim.DAY_START_HOUR * 60 + (t % MarketSim.TICKS_PER_DAY) * 15
			txt = "%02d:%02d" % [(mins / 60) % 24, mins % 60]
		draw_line(Vector2(x, _plot.end.y), Vector2(x, _plot.end.y + 2), UI.MUTED)
		draw_string(UI.font, Vector2(x + 1, y0 + 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.MUTED)
