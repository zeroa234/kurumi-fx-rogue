class_name TutorialDirector
extends Node
## 交易场景中的教学/剧情步骤导演。
## step 字段：
##   dialog: [对话行]      开始时先播放
##   msg: "bbcode"          开始时弹出说明（暂停）
##   objective: "bbcode"    左上角目标文字
##   lock / unlock: [控件名]  buy sell close speed lots sl tp tabs ...
##   highlight: 控件名
##   script: [时间线条目]   t 为相对当前 tick 的偏移（同 TradeSession.cfg.script）
##   speed: n              开始时设定速度
##   until: 条件            满足后进入下一步（缺省 = 立即）
##   finish: true           这一步完成后结束交易
## 条件 type：open{side,symbol,min_lots} close{profit} sl_set tp_set any_sl equity{value}
##   ticks{n} time{day,hour} tab{index} speed_any positions{n} margin_below{level} flat manual
##   any{of:[条件...]} all{of:[条件...]}

signal step_changed(i: int)

var screen: TradeScreen
var steps: Array = []
var i := -1
var _cond := {}
var _start_tick := 0
var _flags := {}

func _init(s: TradeScreen, st: Array) -> void:
	screen = s
	steps = st

func start() -> void:
	screen.objective_event.connect(_on_obj)
	screen.session.ticked.connect(_on_tick)
	screen._tabbar.tab_changed.connect(func(t): _flags["tab_%d" % t] = true; _check())
	_advance()

func all_done() -> bool:
	return i >= steps.size()

func _advance() -> void:
	i += 1
	step_changed.emit(i)
	if i >= steps.size():
		screen.set_objective("")
		return
	var st: Dictionary = steps[i]
	_cond = st.get("until", {})
	_start_tick = screen.session.market.tick
	_flags.clear()
	if st.has("unlock"):
		screen.lock(st.unlock, false)
	if st.has("lock"):
		screen.lock(st.lock, true)
	if st.has("script"):
		for e in st.script:
			var ee: Dictionary = e.duplicate(true)
			if int(ee.get("t", 0)) <= 0:
				screen.session.run_now(ee)
				continue
			ee.at = screen.session.market.tick + int(ee.get("t", 0))
			screen.session.timeline.append(ee)
		screen.session.timeline.sort_custom(func(a, b): return a.at < b.at)
	if st.has("lots"):
		screen.lots = float(st.lots)
		screen._refresh_order()
	if st.has("select"):
		screen._select_symbol(st.select)
	screen.set_objective(st.get("objective", ""))
	if st.has("dialog"):
		screen._on_script_dialog(st.dialog)
		while screen._modal_open:
			await get_tree().process_frame
	if st.has("msg"):
		screen.show_message(st.msg)
		while screen._modal_open:
			await get_tree().process_frame
	if st.has("highlight"):
		screen.highlight(st.highlight)
	if st.has("speed"):
		screen._set_speed(int(st.speed), true)
	if st.get("finish", false) and _cond.is_empty():
		i = steps.size()
		screen.set_objective("")
		screen.session.force_finish("goal")
		return
	_check()

func _on_tick() -> void:
	_check()

func _on_obj(kind: String, data: Dictionary) -> void:
	_flags[kind] = true
	if kind == "close":
		_flags["close_pnl"] = float(data.get("pnl", 0.0))
	if kind == "open":
		var p: Account.Position = data.pos
		_flags["open_side"] = p.side
		_flags["open_symbol"] = p.symbol
		_flags["open_lots"] = p.lots
		_flags["open_sl"] = p.sl
		_flags["open_tp"] = p.tp
	_check()

func _check() -> void:
	if i < 0 or i >= steps.size() or screen._modal_open:
		return
	if _cond.is_empty() or _met(_cond):
		var st: Dictionary = steps[i]
		if st.get("finish", false):
			i = steps.size()
			screen.set_objective("")
			screen.session.force_finish("goal")
			return
		Sfx.play("ok")
		_advance()

func _met(c: Dictionary) -> bool:
	var s := screen.session
	var acc := s.account
	match String(c.get("type", "")):
		"open":
			if not _flags.has("open"):
				return false
			if c.has("side") and int(_flags.open_side) != int(c.side):
				return false
			if c.has("symbol") and _flags.open_symbol != c.symbol:
				return false
			if c.has("min_lots") and float(_flags.open_lots) < float(c.min_lots) - 0.001:
				return false
			if c.get("with_sl", false) and float(_flags.open_sl) <= 0.0:
				return false
			if c.get("with_tp", false) and float(_flags.open_tp) <= 0.0:
				return false
			return true
		"close":
			if not _flags.has("close"):
				return false
			if c.get("profit", false) and float(_flags.get("close_pnl", 0.0)) <= 0.0:
				return false
			return true
		"flat":
			return acc.positions.is_empty()
		"sl_set":
			for p in acc.positions:
				if p.sl > 0.0:
					return true
			return false
		"tp_set":
			for p in acc.positions:
				if p.tp > 0.0:
					return true
			return false
		"pips_sl":
			return screen.sl_pips > 0.0
		"pips_tp":
			return screen.tp_pips > 0.0
		"equity":
			return acc.equity() >= float(c.value)
		"ticks":
			return s.market.tick - _start_tick >= int(c.n)
		"time":
			return s.market.tick >= s.tick_at(int(c.get("day", 0)), int(c.get("hour", 7)), int(c.get("minute", 0)))
		"tab":
			return _flags.has("tab_%d" % int(c.index)) or screen._tabbar.current_tab == int(c.index)
		"speed_any":
			return screen.speed > 0
		"positions":
			return acc.positions.size() >= int(c.n)
		"margin_below":
			return acc.margin_level() < float(c.level)
		"manual":
			return false
		"any":
			for sub in c.get("of", []):
				if _met(sub):
					return true
			return false
		"all":
			for sub in c.get("of", []):
				if not _met(sub):
					return false
			return true
	return false
