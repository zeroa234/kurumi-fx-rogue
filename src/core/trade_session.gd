class_name TradeSession
extends RefCounted
## 一段交易（剧情一幕 / 肉鸽一个节点）：把行情、事件、账户、久留美心理串起来，并执行脚本时间线。
##
## cfg 字段：
##   seed, start_date("YYYY-MM-DD"), days, warmup_days, balance, credit, broker{}, symbols[],
##   market_params{}, event_params{}, act, random_news, sns, overrides{start_prices,pegs,units},
##   mental, goal{equity}, end_on_bust, script[{t | day+hour+minute, do, ...}], calendar_free

signal ticked
signal day_changed(day: int)
signal finished(result: Dictionary)
signal alert(kind: String, text: String)
signal script_dialog(lines: Array)
signal script_pause(text: String)
signal script_signal(name: String, data: Dictionary)

var cfg: Dictionary
var mods: Mods
var market: MarketSim
var events: EventEngine
var account: Account
var kurumi: Kurumi
var start_unix: int
var day0 := 0
var days := 3
var symbols: Array[String] = []
var done := false
var result := {}
var timeline: Array = []
var _last_day := -1
var _float_said := 0

func _init(config: Dictionary, shared_mods: Mods = null) -> void:
	cfg = config
	mods = shared_mods if shared_mods != null else Mods.new()
	var seed_value: int = int(cfg.get("seed", 0))
	if seed_value == 0:
		seed_value = randi()
	market = MarketSim.new(seed_value)
	var mp: Dictionary = cfg.get("market_params", {})
	var ov: Dictionary = cfg.get("overrides", {}).duplicate(true)
	ov["params"] = mp
	market.setup(DB.get_json("res://data/market/units.json"), DB.get_json("res://data/market/instruments.json"), ov)
	start_unix = GameDate.next_weekday(GameDate.parse(cfg.get("start_date", "2014-02-03")))
	days = int(cfg.get("days", 3))
	for s in cfg.get("symbols", ["USDJPY", "EURJPY", "AUDJPY"]):
		symbols.append(s)
	events = EventEngine.new(market, mods, seed_value)
	events.act = int(cfg.get("act", 1))
	for k in cfg.get("event_params", {}):
		events.params[k] = cfg.event_params[k]
	events.random_news = bool(cfg.get("random_news", true))
	events.enable_sns = bool(cfg.get("sns", true))
	events.affi_enabled = bool(cfg.get("affi", false))
	events.weekday_fn = func(d: int) -> int: return GameDate.weekday(date_of_day(d))
	account = Account.new(market, mods, float(cfg.get("balance", 300000.0)), cfg.get("broker", {}))
	account.credit = float(cfg.get("credit", 0.0))
	kurumi = Kurumi.new(mods, float(cfg.get("mental", 80.0)), seed_value)
	account.closed.connect(_on_closed)
	account.margin_warning.connect(_on_margin_warning)
	account.stopped_out.connect(_on_stopped_out)
	account.zero_cut_used.connect(func(_a): kurumi.say("zero_cut", true))
	account.swap_settled.connect(_on_swap)
	events.news_posted.connect(_on_news)
	# 预热：让图表有历史
	var warm: int = int(cfg.get("warmup_days", 5))
	events.random_news = false
	market.warmup(warm)
	events.random_news = bool(cfg.get("random_news", true))
	# 预热用掉的账户历史清零
	account.stats.max_equity = account.equity()
	day0 = market.day_index()
	_last_day = day0
	if bool(cfg.get("calendar", true)):
		events.schedule_days(day0, days)
	_build_script()

# ---------------------------------------------------------------- 日期

## 市场第 d 天对应的日期
func date_of_day(d: int) -> int:
	return GameDate.trading_day(start_unix, d - day0)

func session_day() -> int:
	return market.day_index() - day0

func session_tick() -> int:
	return market.tick - day0 * MarketSim.TICKS_PER_DAY

func ticks_left() -> int:
	return days * MarketSim.TICKS_PER_DAY - session_tick()

func now_text() -> String:
	var c := market.clock()
	var d := date_of_day(market.day_index())
	# 07:00 之前属于下一个日历日
	if c.x < MarketSim.DAY_START_HOUR:
		d += 86400
	return "%s %02d:%02d" % [GameDate.fmt(d), c.x, c.y]

## 交易日内某时刻的绝对 tick
func tick_at(session_day_k: int, hour: int, minute: int) -> int:
	return (day0 + session_day_k) * MarketSim.TICKS_PER_DAY + EventEngine.tick_in_day(hour, minute)

# ---------------------------------------------------------------- 脚本

func _build_script() -> void:
	for s in cfg.get("script", []):
		var e: Dictionary = s.duplicate(true)
		if e.has("t"):
			e.at = day0 * MarketSim.TICKS_PER_DAY + int(e.t)
		else:
			e.at = tick_at(int(e.get("day", 0)), int(e.get("hour", 7)), int(e.get("minute", 0)))
		timeline.append(e)
	timeline.sort_custom(func(a, b): return a.at < b.at)

func _run_script() -> void:
	while not timeline.is_empty() and int(timeline[0].at) <= market.tick:
		var e: Dictionary = timeline.pop_front()
		match String(e.get("do", "")):
			"news":
				var def: Dictionary = e.get("def", {})
				if e.has("template"):
					for n in events.news_templates:
						if n.id == e.template:
							def = n.duplicate(true)
				events.fire(def, false)
			"text":
				events.post_text(e.get("title", ""), e.get("kind", "news"), e.get("icon", "paper"), int(e.get("severity", 2)))
			"sns":
				events.post_sns(e.get("who", "@anon"), e.get("text", ""))
			"guide":
				market.guide_to(e.symbol, float(e.price), int(e.get("ticks", 4)))
			"effect":
				market.add_effect(e.target, e.channel, float(e.mag), int(e.get("delay", 0)), int(e.get("ramp", 1)), int(e.get("dur", 0)), float(e.get("fade", 0.0)), e.get("tag", ""))
			"peg":
				market.instruments[e.symbol].peg = {"floor": float(e.floor), "pressure": float(e.get("pressure", 0.0))}
			"peg_break":
				market.break_peg(e.symbol, float(e.get("magnitude", -1.0)), float(e.get("overshoot", 0.5)), int(e.get("recover", 24)))
			"halt":
				market.instruments[e.symbol].halted = bool(e.get("on", true))
			"params":
				for k in e.get("market", {}):
					market.params[k] = e.market[k]
				for k in e.get("events", {}):
					events.params[k] = e.events[k]
			"say":
				kurumi.say_text(e.get("text", ""), e.get("face", "normal"))
			"dialog":
				script_dialog.emit(e.get("lines", []))
			"pause":
				script_pause.emit(e.get("text", ""))
			"indicator":
				events.schedule_indicator(e.id, int(e.get("day", session_day())) + day0, e.get("forced", {}))
			"rate":
				market.units[e.unit].rate = float(e.value)
			_:
				script_signal.emit(String(e.get("do", "")), e)

# ---------------------------------------------------------------- 推进

func advance() -> void:
	if done:
		return
	_run_script()
	events.update()
	market.step()
	account.process_tick()
	var eq := account.equity()
	var ratio := account.floating_total() / maxf(1.0, eq - account.floating_total())
	kurumi.on_tick(ratio, not account.positions.is_empty())
	var d := market.day_index()
	if d != _last_day:
		_on_new_day(d)
	ticked.emit()
	if kurumi.is_broken() and bool(cfg.get("end_on_broken", true)):
		_finish("broken")
		return
	if bool(cfg.get("end_on_bust", true)) and account.positions.is_empty() and account.equity() < 1000.0:
		_finish("bust")
		return
	var goal: Dictionary = cfg.get("goal", {})
	if goal.has("equity_early") and account.equity() >= float(goal.equity_early):
		_finish("goal")
		return
	if session_tick() >= days * MarketSim.TICKS_PER_DAY:
		_finish("time")

func _on_new_day(d: int) -> void:
	_last_day = d
	# 换日：掉期（周三→周四换日计 3 天）
	var prev_date := date_of_day(d - 1)
	var mult := 3 if GameDate.weekday(prev_date) == 3 else 1
	account.settle_swap(mult)
	kurumi.daily_regen()
	# 周末跳空：前一交易日是周五
	if GameDate.weekday(prev_date) == 5:
		for code in market.unit_order:
			var u: MarketSim.Unit = market.units[code]
			u.x += market.rng.randfn(0.0, u.vol * 0.5 * market.params.vol_mult)
	day_changed.emit(d - day0)

func _finish(reason: String) -> void:
	if done:
		return
	done = true
	result = {
		"reason": reason,
		"equity": account.equity(),
		"balance": account.balance,
		"floating": account.floating_total(),
		"debt": account.debt,
		"start": float(cfg.get("balance", 0.0)),
		"stats": account.stats.duplicate(),
		"mental": kurumi.mental,
		"history": account.history.duplicate(),
	}
	finished.emit(result)

## 结束前平掉所有持仓（节点结束时）
func close_out() -> void:
	account.close_all("期末平仓")
	account.settle_negative()

func force_finish(reason := "quit") -> void:
	_finish(reason)

## 断开循环引用（离开交易画面时调用）
func dispose() -> void:
	events.weekday_fn = Callable()

# ---------------------------------------------------------------- 回调

func _on_closed(pos: Account.Position, pnl: float, reason: String) -> void:
	var eq_before := account.equity() - pnl
	kurumi.on_closed(pnl, eq_before, reason)
	if reason == "止损" and pnl < 0.0:
		alert.emit("sl", "止损成交 %s" % GameDate.yen(pnl, true))
	elif reason == "止盈":
		alert.emit("tp", "止盈成交 %s" % GameDate.yen(pnl, true))

func _on_margin_warning(level: float) -> void:
	kurumi.on_margin_call()
	alert.emit("margin", "维持率 %.0f%%！快到强平线 %.0f%% 了" % [level, account.stopout_level()])

func _on_stopped_out(eq_after: float) -> void:
	kurumi.on_stop_out()
	var t := "强制平仓（ロスカット）！"
	if account.debt > 0.0:
		t += " 产生不足金 %s" % GameDate.yen(account.debt)
	alert.emit("stopout", t)

func _on_swap(total: float) -> void:
	if total > 0.0 and total > account.equity() * 0.002:
		kurumi.say("swap")

func _on_news(item: Dictionary) -> void:
	if int(item.get("severity", 1)) >= 2:
		kurumi.say("news")

# ---------------------------------------------------------------- 便捷操作（UI 调用）

func buy(symbol: String, lots: float, sl := 0.0, tp := 0.0) -> Variant:
	var r = account.open_position(symbol, 1, lots, sl, tp)
	if r is Account.Position:
		kurumi.say("open_long")
	return r

func sell(symbol: String, lots: float, sl := 0.0, tp := 0.0) -> Variant:
	var r = account.open_position(symbol, -1, lots, sl, tp)
	if r is Account.Position:
		kurumi.say("open_short")
	return r
