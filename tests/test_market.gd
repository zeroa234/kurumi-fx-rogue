extends Node
## 引擎自检：godot --headless --path . res://tests/test_market.tscn
## 打印各品种日波动、事件数量，检查账户/强平/零cut/钉住撤销。失败时退出码 1。

var fails := 0

func check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  ", msg)
	else:
		fails += 1
		printerr("  FAIL ", msg)

func _ready() -> void:
	test_market_stats()
	test_account_basic()
	test_stopout_debt()
	test_zero_cut()
	test_peg_break()
	test_session_events()
	print("== 失败 %d ==" % fails)
	get_tree().quit(1 if fails > 0 else 0)

func new_market(seed_value := 42, ov := {}) -> MarketSim:
	var m := MarketSim.new(seed_value)
	m.setup(DB.get_json("res://data/market/units.json"), DB.get_json("res://data/market/instruments.json"), ov)
	return m

func test_market_stats() -> void:
	print("[行情统计] 120 个交易日")
	var m := new_market(7)
	var days := 120
	var start := {}
	for s in m.symbol_order:
		start[s] = m.instruments[s].mid
	m.warmup(days)
	for s in m.symbol_order:
		var ins: MarketSim.Instrument = m.instruments[s]
		var rets: Array[float] = []
		var intraday: Array[float] = []
		for d in range(1, days):
			var c0 := ins.c[d * 96 - 1]
			var c1 := ins.c[(d + 1) * 96 - 1]
			rets.append(log(c1 / c0))
			var hi := -INF
			var lo := INF
			for i in range(d * 96, (d + 1) * 96):
				hi = maxf(hi, ins.h[i])
				lo = minf(lo, ins.l[i])
			intraday.append((hi - lo) / c0)
		var mean := 0.0
		for r in rets: mean += r
		mean /= rets.size()
		var v := 0.0
		for r in rets: v += (r - mean) * (r - mean)
		var sd := sqrt(v / rets.size())
		var rng_avg := 0.0
		for r in intraday: rng_avg += r
		rng_avg /= intraday.size()
		var nan := false
		for x in ins.c:
			if is_nan(x) or x <= 0.0:
				nan = true
				break
		print("  %-7s start %-10s end %-10s 日波动 %.2f%%  平均日内幅度 %.2f%%  猎杀止损 %d" % [s, m.format_price(ins, start[s]), m.format_price(ins, ins.mid), sd * 100.0, rng_avg * 100.0, ins.hunts])
		check(not nan, s + " 价格无 NaN/非正")
		check(sd > 0.002 and sd < 0.03, s + " 日波动在合理区间")

func test_account_basic() -> void:
	print("[账户] 开平仓与损益")
	var m := new_market(1)
	m.warmup(2)
	var md := Mods.new()
	var acc := Account.new(m, md, 300000.0, {"leverage": 25.0})
	var ins := m.get_ins("USDJPY")
	var lots := acc.max_lots("USDJPY")
	print("  USDJPY %.3f  最大手数 %.1f  1手证拠金 %.0f" % [ins.mid, lots, acc.margin_for("USDJPY", 1.0)])
	check(lots > 0.0, "可开仓")
	var r = acc.open_position("USDJPY", 1, 1.0)
	check(r is Account.Position, "开多 1 手")
	var p: Account.Position = r
	var before := acc.equity()
	# 手动把价格抬高 1 円
	ins.offset += log((ins.mid + 1.0) / ins.mid)
	ins.mid = m.price_of(ins)
	var fl := acc.floating(p)
	print("  上涨 1 円后含み益 %.0f（期望约 10000）" % fl)
	check(absf(fl - 10000.0) < 200.0, "1 手 1 円 ≈ 1 万円")
	acc.close_position(p)
	check(acc.positions.is_empty() and acc.balance > before, "平仓后余额增加")

func test_stopout_debt() -> void:
	print("[强平] 国内业者：跳空 → 不足金")
	var m := new_market(2)
	m.warmup(2)
	var md := Mods.new()
	var acc := Account.new(m, md, 300000.0, {"leverage": 25.0, "stopout": 100.0, "zero_cut": false})
	var lots := acc.max_lots("EURJPY")
	acc.open_position("EURJPY", 1, lots)
	# 欧元暴跌 15%（一次性跳空）
	m.add_effect("EUR", "level", -0.16, 0, 1, 0, 0.0)
	m.step()
	acc.process_tick()
	print("  强平后 余额 %.0f  不足金 %.0f  持仓 %d" % [acc.balance, acc.debt, acc.positions.size()])
	check(acc.positions.is_empty(), "已被强平")
	check(acc.debt > 0.0, "产生不足金（借金）")

func test_zero_cut() -> void:
	print("[强平] 海外业者：零 cut")
	var m := new_market(3)
	m.warmup(2)
	var md := Mods.new()
	var acc := Account.new(m, md, 300000.0, {"leverage": 888.0, "stopout": 20.0, "zero_cut": true})
	acc.open_position("EURJPY", 1, acc.max_lots("EURJPY"))
	m.add_effect("EUR", "level", -0.05, 0, 1, 0, 0.0)
	m.step()
	acc.process_tick()
	print("  余额 %.0f  不足金 %.0f" % [acc.balance, acc.debt])
	check(acc.debt == 0.0 and acc.balance == 0.0, "负余额被清零")

func test_peg_break() -> void:
	print("[钉住] EUR/CHF 1.20 下限 → 撤销")
	var m := new_market(4, {"start_prices": {"EURCHF": 1.2050}, "pegs": {"EURCHF": 1.20}})
	# 让瑞郎持续升值压力
	m.add_effect("CHF", "drift", 0.004, 0, 1, 96 * 30)
	m.warmup(20)
	var ins := m.get_ins("EURCHF")
	var lo := INF
	for x in ins.l:
		lo = minf(lo, x)
	print("  20 天最低 %.5f  压力 %.4f" % [lo, ins.peg.pressure])
	check(lo >= 1.1999, "下限守住")
	m.break_peg("EURCHF", 0.33, 0.35, 24)
	var low2 := INF
	for i in 30:
		m.step()
		low2 = minf(low2, ins.l[ins.l.size() - 1])
	print("  撤销后最低 %.5f  30 tick 后 %.5f" % [low2, ins.mid])
	check(low2 < 0.95, "暴跌到 0.95 以下")
	check(ins.mid > low2, "之后有反弹")

func test_session_events() -> void:
	print("[会话] 20 天随机事件")
	var s := TradeSession.new({"seed": 99, "days": 20, "balance": 300000.0, "act": 3, "event_params": {"news_per_day": 3.0}})
	var counts := {}
	s.events.news_posted.connect(func(it): counts[it.kind] = int(counts.get(it.kind, 0)) + 1)
	var sns := [0]
	s.events.sns_posted.connect(func(_it): sns[0] += 1)
	while not s.done:
		s.advance()
	print("  新闻分布 ", counts, "  SNS ", sns[0], "  结束原因 ", s.result.reason)
	check(counts.get("indicator", 0) >= 4, "有经济指标发布")
	check(s.result.reason == "time", "按时结束")
	print("  结束日期 ", s.now_text())
