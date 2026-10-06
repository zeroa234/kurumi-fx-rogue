extends Node
## 平衡模拟：godot --headless --path . res://tests/sim_balance.tscn -- --runs=40 --meta=0 --risk=0.02
## 机器人策略：1 小时均线 20/75 顺势 + 止损 1.2×日波动 + 止盈 2R，单笔风险 risk×净值。
## 非交易节点按平均效果处理（休息=打工，事件=小幅随机，商店=买最便宜的手法）。

var risk := 0.02
var meta_level := 0
var runs := 30
var broker := "overseas"
var oracle := false

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--runs="): runs = int(a.substr(7))
		elif a.begins_with("--meta="): meta_level = int(a.substr(7))
		elif a.begins_with("--risk="): risk = float(a.substr(7))
		elif a.begins_with("--broker="): broker = a.substr(9)
		elif a == "--oracle": oracle = true
	_apply_meta(meta_level)
	var reached := [0, 0, 0, 0]
	var nets: Array = []
	var t0 := Time.get_ticks_msec()
	for i in runs:
		var r := _sim_run(1000 + i)
		reached[clampi(int(r.act_reached), 0, 3)] += 1
		nets.append(r.max_net)
		print("run %d: 到达幕 %d  通关 %s  最高净资产 %s  结束 %s" % [i, r.act_reached, r.victory, GameDate.yen(r.max_net), r.reason])
	nets.sort()
	print("== 养成等级 %d / 风险 %.3f / %s / oracle=%s ==" % [meta_level, risk, broker, oracle])
	print("死在第1幕 %d · 死在第2幕 %d · 死在第3幕 %d · 通关 %d （共 %d 局）" % [reached[1], reached[2], reached[3] - 0, reached[0], runs])
	print("最高净资产中位数 %s  用时 %.1fs" % [GameDate.yen(nets[nets.size() / 2]), (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit()

func _apply_meta(lv: int) -> void:
	# 用内存存档模拟局外养成（不写盘）
	Save.data = Save._default()
	Save.data.story.tutorial_done = true
	for u in ["friend_mochiko", "friend_mebuki"]:
		Save.unlock(u)
	if lv <= 0:
		return
	for n in DB.get_json("res://data/run/meta.json").nodes:
		var mx: int = n.cost.size()
		Save.data.meta.levels[n.id] = mini(mx, int(ceil(mx * lv / 3.0)))
		if n.effect.has("unlock"):
			Save.unlock(n.effect.unlock)

func _sim_run(seed_v: int) -> Dictionary:
	var run := RunState.create({"broker": broker, "friends": ["mochiko"], "seed": seed_v})
	var out := {"act_reached": 1, "victory": false, "max_net": run.money, "reason": ""}
	while true:
		var av := run.available()
		if av.is_empty():
			break
		# 偏好：交易 > 休息 > 商店 > 事件 > 精英
		var pick: String = av[0]
		var best := -1
		for id in av:
			var n := run.node(id)
			var score: int = {"boss": 10, "trade": 5, "rest": 4, "shop": 3, "event": 2, "elite": 1}.get(n.type, 0)
			if score > best:
				best = score
				pick = id
		var node := run.enter(pick)
		match String(node.type):
			"trade", "elite", "boss":
				var res := _bot_session(run, node)
				var info := run.settle_trade(node, res, {})
				run.complete_current()
				if res.reason == "broken":
					out.reason = "broken"
					break
				if node.type == "elite":
					var rs := run.roll_relics(1, "uncommon")
					if not rs.is_empty(): run.add_relic(rs[0].id)
				if node.type == "boss":
					if not info.get("passed", false):
						out.reason = "target %s < %s" % [GameDate.yen(run.net()), GameDate.yen(run.target())]
						break
					var rr := run.roll_relics(1, "rare")
					if not rr.is_empty(): run.add_relic(rr[0].id)
					if run.act >= 3:
						out.victory = true
						out.act_reached = 0
						break
					run.next_act()
					out.act_reached = run.act
				if run.money < 10000.0:
					out.reason = "bankrupt"
					break
			"rest":
				run.money += run.act_money_base() * run.mods.get_v("work_pay_mult")
				run.complete_current()
			"shop":
				var shop := run.gen_shop()
				for s in shop.relics:
					if run.fp >= int(s.price):
						run.fp -= int(s.price)
						run.add_relic(s.id)
						break
				run.complete_current()
			_:
				run.fp += 10
				run.complete_current()
		out.max_net = maxf(out.max_net, run.net())
	return out

func _bot_session(run: RunState, node: Dictionary) -> Dictionary:
	var cfg := run.trade_config(node)
	cfg.sns = false
	var s := TradeSession.new(cfg, run.mods)
	var syms := ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY"]
	while not s.done:
		s.advance()
		if s.market.tick % 4 != 0:
			continue
		for sym in syms:
			var has := false
			for p in s.account.positions:
				if p.symbol == sym:
					has = true
			if has:
				continue
			var cs := s.market.candles(sym, 4, 80)
			if cs.size() < 76:
				continue
			var m20 := 0.0
			var m75 := 0.0
			for k in range(cs.size() - 20, cs.size()):
				m20 += cs[k][3]
			for k in range(cs.size() - 75, cs.size()):
				m75 += cs[k][3]
			m20 /= 20.0
			m75 /= 75.0
			var ins := s.market.get_ins(sym)
			var px := ins.mid
			var side := 0
			if oracle:
				var ub: MarketSim.Unit = s.market.units[ins.base]
				var uq: MarketSim.Unit = s.market.units[ins.quote]
				var rd := (1 if ub.regime == 1 else (-1 if ub.regime == 2 else 0)) - (1 if uq.regime == 1 else (-1 if uq.regime == 2 else 0))
				side = signi(rd)
			elif m20 > m75 * 1.0005 and px > m20:
				side = 1
			elif m20 < m75 * 0.9995 and px < m20:
				side = -1
			if side == 0:
				continue
			var stop := s.market.daily_vol(ins) * px * 1.2
			var per_lot_risk := stop * ins.contract * s.market.jpy_value(ins.quote)
			var lots := floorf(s.account.equity() * risk / per_lot_risk * 10.0) / 10.0
			lots = minf(lots, s.account.max_lots(sym) * 0.8)
			if lots < 0.1:
				continue
			s.account.open_position(sym, side, lots, px - side * stop, px + side * stop * 2.0)
	s.close_out()
	var r := s.result
	r.balance = s.account.balance
	r.debt = s.account.debt
	r.mental = s.kurumi.mental
	s.dispose()
	return r
