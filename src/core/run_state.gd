class_name RunState
extends RefCounted
## 肉鸽一局的状态：地图、资金、借金、FP、メンタル、手法、道具、诅咒、仲间。
## 节点之间持仓全部平掉，资金 = 现金。Boss 目标比较「净资产」（资金 − 借金）。

const LOAN_RATE := 1.095 # 年利 109.5%
const MAP_LAYERS := 7
const ACT_MONEY_BASE := [50000.0, 200000.0, 800000.0, 3000000.0]

var seed_value := 0
var rng := RandomNumberGenerator.new()
var act := 1
var layer := -1
var map: Array = [] # [layer][node]
var current := ""
var money := 300000.0
var start_money := 300000.0
var debt := 0.0
var fp := 0
var mental := 80.0
var broker_id := "overseas"
var friends: Array = []
var relics: Array = []
var items: Array = []
var curses: Array = []
var temp_mods := {}
var skip_next := false
var ascension := 0
var days_elapsed := 0
var nodes_cleared := 0
var max_net := 0.0
var trades := 0
var wins := 0
var stopouts := 0
var bosses_beaten: Array = []
var used_specials := {}
var friend_charges := {}
var log_lines: Array = []
var ended := false
var victory := false
var end_reason := ""
var in_node := "" # 进入交易节点后、结算前的节点 id（防 SL 读档）
var shop_cache := {}
var credit_given_act := 0

var mods := Mods.new()

# ================================================================ 创建

static func create(opts: Dictionary) -> RunState:
	var r := RunState.new()
	r.seed_value = int(opts.get("seed", 0))
	if r.seed_value == 0:
		r.seed_value = randi() % 1000000000 + 1
	r.rng.seed = r.seed_value
	r.broker_id = opts.get("broker", "overseas")
	r.friends = opts.get("friends", [])
	r.ascension = int(opts.get("ascension", 0))
	r.start_money = 300000.0 + Save.meta_level("money1") * 50000.0
	r.money = r.start_money
	r.rebuild_mods()
	r.mental = minf(80.0 + Save.meta_level("mental1") * 5.0, r.mods.get_v("mental_max"))
	if r.ascension >= 2:
		r.mental -= 10.0
	if opts.has("start_relic") and opts.start_relic != "":
		r.relics.append(opts.start_relic)
	var b := r.broker()
	for g in b.get("grant", []):
		r.used_specials["grant_" + g] = true
	r.rebuild_mods()
	r.max_net = r.money
	r._gen_map()
	for f in r.friends:
		r.friend_charges[f] = 0
	return r

func broker() -> Dictionary:
	return DB.find("res://data/run/brokers.json", "brokers", broker_id)

func act_def() -> Dictionary:
	var acts: Array = DB.get_json("res://data/run/nodes.json").acts
	var a: Dictionary = acts[mini(act, acts.size()) - 1].duplicate(true)
	if act > acts.size():
		# 无尽：目标与波动逐幕递增
		var en: Dictionary = DB.get_json("res://data/run/nodes.json").endless
		var extra := act - acts.size()
		a.target = float(a.target) * pow(float(en.target_mult), extra)
		a.market.vol_mult = float(a.market.vol_mult) + float(en.vol_step) * extra
		a.name = "无尽 · 第%d年" % act
	return a

func target() -> float:
	var t := float(act_def().target)
	if ascension >= 1:
		t *= 1.15
	if ascension >= 6:
		t *= 1.15
	if ascension >= 10 and act == 3:
		t = maxf(t, 30000000.0)
	return t

func net() -> float:
	return money - debt

func act_money_base() -> float:
	return ACT_MONEY_BASE[clampi(act - 1, 0, ACT_MONEY_BASE.size() - 1)]

func item_slots() -> int:
	return 3 + Save.meta_level("slots_item")

func friend_slots() -> int:
	return 1 + Save.meta_level("slots_friend")

# ================================================================ 修正

func rebuild_mods() -> void:
	mods = Mods.new()
	var meta: Array = DB.get_json("res://data/run/meta.json").nodes
	for n in meta:
		var lv := Save.meta_level(n.id)
		if lv <= 0:
			continue
		var eff: Dictionary = n.get("effect", {})
		if eff.has("mods"):
			var layer_v := {}
			for k in eff.mods:
				if String(k).ends_with("_mult"):
					layer_v[k] = pow(float(eff.mods[k]), lv)
				else:
					layer_v[k] = float(eff.mods[k]) * lv
			mods.set_layer("meta_" + n.id, layer_v)
	for rid in relics:
		var r := relic_def(rid)
		if not r.is_empty():
			mods.set_layer("relic_" + rid, r.get("mods", {}))
	for fid in friends:
		var f := friend_def(fid)
		mods.set_layer("friend_" + fid, f.get("passive", {}))
	for c in curses:
		var cd := curse_def(c)
		mods.set_layer("curse_" + c, cd.get("mods", {}))
	var asc := {}
	if ascension >= 3:
		asc["spread_mult"] = 1.2
	if ascension >= 5:
		asc["news_lead"] = -1
	if ascension >= 4:
		asc["shop_discount"] = -0.15
	mods.set_layer("ascension", asc)
	if not temp_mods.is_empty():
		mods.set_layer("temp", temp_mods)

func relic_def(id: String) -> Dictionary:
	return DB.find("res://data/run/relics.json", "relics", id)

func item_def(id: String) -> Dictionary:
	return DB.find("res://data/run/items.json", "items", id)

func curse_def(id: String) -> Dictionary:
	return DB.find("res://data/run/items.json", "curses", id)

func friend_def(id: String) -> Dictionary:
	return DB.find("res://data/run/friends.json", "friends", id)

func has_relic(id: String) -> bool:
	return relics.has(id)

# ================================================================ 地图

func _gen_map() -> void:
	map.clear()
	layer = -1
	current = ""
	var weights := {"trade": 40.0, "elite": 12.0, "event": 22.0, "shop": 12.0, "rest": 14.0}
	if ascension >= 8:
		weights.rest = 7.0
	for li in MAP_LAYERS:
		var row: Array = []
		var count := 1
		if li > 0 and li < MAP_LAYERS - 1:
			count = rng.randi_range(2, 4)
		for ni in count:
			var t := "trade"
			if li == MAP_LAYERS - 1:
				t = "boss"
			elif li == 0:
				t = "trade"
			else:
				var w := weights.duplicate()
				if li == 1:
					w.elite = 0.0
					w.shop = 0.0
					w.rest = 0.0
				if li == MAP_LAYERS - 2:
					w.rest *= 2.5
					w.shop *= 1.6
				t = _weighted(w)
			var node := {"id": "a%d_l%d_n%d" % [act, li, ni], "layer": li, "idx": ni, "type": t, "next": [], "done": false}
			if t == "elite":
				var els: Array = DB.get_json("res://data/run/nodes.json").elites
				node.elite = els[rng.randi() % els.size()].id
			elif t == "boss":
				var bs: Array = []
				for b in DB.get_json("res://data/run/nodes.json").bosses:
					if int(b.act) == clampi(act, 1, 3):
						bs.append(b)
				node.boss = bs[rng.randi() % bs.size()].id
			elif t == "event":
				node.event = _pick_event()
			row.append(node)
		map.append(row)
	# 连线：每个节点连到下一层 1~2 个相邻节点，保证下一层每个节点都有入口
	for li in MAP_LAYERS - 1:
		var a: Array = map[li]
		var b: Array = map[li + 1]
		for ni in a.size():
			var pos := float(ni) / maxf(1.0, a.size() - 1) * (b.size() - 1) if a.size() > 1 else (b.size() - 1) / 2.0
			var j := int(round(pos))
			a[ni].next.append(b[j].id)
			if rng.randf() < 0.45:
				var j2 := clampi(j + (1 if rng.randf() < 0.5 else -1), 0, b.size() - 1)
				if not a[ni].next.has(b[j2].id):
					a[ni].next.append(b[j2].id)
		for nb in b:
			var has_in := false
			for na in a:
				if na.next.has(nb.id):
					has_in = true
			if not has_in:
				var k := clampi(int(round(float(nb.idx) / maxf(1.0, b.size() - 1) * (a.size() - 1))), 0, a.size() - 1)
				a[k].next.append(nb.id)

func _weighted(w: Dictionary) -> String:
	var total := 0.0
	for k in w:
		total += float(w[k])
	var r := rng.randf() * total
	for k in w:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "trade"

func _pick_event() -> String:
	var pool: Array = []
	for e in DB.get_json("res://data/run/events.json").events:
		if not e.get("acts", [1, 2, 3]).has(float(clampi(act, 1, 3))) and not e.get("acts", [1, 2, 3]).has(clampi(act, 1, 3)):
			continue
		if e.has("requires_friend") and not Save.has_unlock("friend_" + e.requires_friend):
			continue
		pool.append(e.id)
	if pool.is_empty():
		return ""
	return pool[rng.randi() % pool.size()]

func node(id: String) -> Dictionary:
	for row in map:
		for n in row:
			if n.id == id:
				return n
	return {}

func available() -> Array:
	if layer < 0:
		return map[0].map(func(n): return n.id)
	var cur := node(current)
	if cur.is_empty() or not cur.done:
		return []
	return cur.next

func enter(id: String) -> Dictionary:
	var n := node(id)
	current = id
	layer = int(n.layer)
	return n

func complete_current() -> void:
	var n := node(current)
	n.done = true
	nodes_cleared += 1
	in_node = ""

# ================================================================ 交易节点

func elite_def(id: String) -> Dictionary:
	return DB.find("res://data/run/nodes.json", "elites", id)

func boss_def(id: String) -> Dictionary:
	return DB.find("res://data/run/nodes.json", "bosses", id)

func symbols() -> Array:
	var out := ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY", "EURUSD"]
	for d in DB.get_json("res://data/market/instruments.json").instruments:
		if d.unlock != "" and (Save.has_unlock(d.unlock) or used_specials.has("grant_" + d.unlock)) and not out.has(d.symbol):
			out.append(d.symbol)
	return out

## 生成交易节点的 TradeSession 配置
func trade_config(n: Dictionary) -> Dictionary:
	var a := act_def()
	var kind: String = n.type
	var days: int = int(a.days_boss) if kind == "boss" else int(a.days_trade)
	var start := GameDate.trading_day(GameDate.next_weekday(GameDate.parse(a.start_date)), days_elapsed_in_act())
	var b := broker()
	var cfg := {
		"seed": seed_value * 31 + hash(n.id) % 100000,
		"start_date": Time.get_date_string_from_unix_time(start),
		"days": days,
		"warmup_days": 6,
		"balance": money,
		"broker": b,
		"symbols": symbols(),
		"act": clampi(act, 1, 3),
		"market_params": a.market.duplicate(),
		"event_params": a.events.duplicate(),
		"mental": mental,
		"end_on_broken": true,
		"affi": friends.has("yasuko"),
		"script": [],
		"overrides": {},
	}
	if ascension >= 7:
		cfg.market_params.hunt_prob = float(cfg.market_params.get("hunt_prob", 0.01)) * 1.6
	# 海外业者：每幕第一个交易节点送入金奖金（赠金）
	if float(b.get("bonus", 0.0)) > 0.0 and credit_given_act < act:
		cfg.credit = money * float(b.bonus)
		credit_given_act = act
	if kind == "elite":
		var e := elite_def(n.get("elite", ""))
		_apply_mod_block(cfg, e)
		cfg.goal_text = "精英：" + e.get("name", "")
	elif kind == "boss":
		var bd := boss_def(n.get("boss", ""))
		_apply_mod_block(cfg, bd)
		if bd.has("pegs"):
			cfg.overrides.pegs = bd.pegs
		if bd.has("start_prices"):
			cfg.overrides.start_prices = bd.start_prices
		cfg.goal = {"equity": target() + debt}
		cfg.goal_text = "BOSS：" + bd.get("name", "")
	else:
		var g := money * (1.0 + float(a.goal_pct))
		cfg.goal = {"equity": g}
	return cfg

func _apply_mod_block(cfg: Dictionary, e: Dictionary) -> void:
	var mult: bool = e.get("mult", false)
	for k in e.get("market", {}):
		if mult and cfg.market_params.has(k) and typeof(e.market[k]) == TYPE_FLOAT:
			cfg.market_params[k] = float(cfg.market_params[k]) * float(e.market[k])
		else:
			cfg.market_params[k] = e.market[k]
	for k in e.get("events", {}):
		if mult and cfg.event_params.has(k) and typeof(e.events[k]) == TYPE_FLOAT:
			cfg.event_params[k] = float(cfg.event_params[k]) * float(e.events[k])
		else:
			cfg.event_params[k] = e.events[k]
	for s in e.get("symbols_add", []):
		if not cfg.symbols.has(s):
			cfg.symbols.append(s)
	for st in e.get("script", []):
		var x: Dictionary = st.duplicate(true)
		if x.has("rand_day"):
			x.day = rng.randi_range(int(x.rand_day[0]), mini(int(x.rand_day[1]), int(cfg.days) - 1))
			x.erase("rand_day")
		if not x.has("hour"):
			x.hour = 7
			x.minute = 15
		match String(x.get("do", "")):
			"indicator":
				var fs: float = float(x.get("forced_surprise", 2.0)) * (1.0 if rng.randf() < 0.5 else -1.0)
				x.forced = {"surprise": fs}
				x.t = 1
				x.erase("hour")
			"peg_break_news":
				x.do = "news"
				x.def = {"id": "peg_break", "kind": "cb", "icon": "bank", "severity": 3, "delay": 0, "instant": true,
					"title": "【速報】央行宣布取消欧元/瑞郎汇率下限", "body": "市场完全没有准备。报价一度消失，价格瞬间崩落。",
					"peg_break": {"symbol": "EURCHF", "magnitude": rng.randf_range(0.18, 0.3), "overshoot": 0.35, "recover": 30}}
		cfg.script.append(x)

func days_elapsed_in_act() -> int:
	return int(used_specials.get("act_days_%d" % act, 0))

## 交易节点结算。返回奖励信息
func settle_trade(n: Dictionary, result: Dictionary, extra: Dictionary) -> Dictionary:
	var a := act_def()
	var before := money
	var after_cash: float = float(result.balance)
	var profit := after_cash - before
	# 滞纳税金诅咒
	if curses.has("tax") and profit > 0.0:
		after_cash -= profit * 0.2
	money = maxf(0.0, after_cash)
	debt += float(result.debt) + float(extra.get("loan", 0.0))
	mental = float(result.mental)
	var days: int = int(a.days_boss) if n.type == "boss" else int(a.days_trade)
	used_specials["act_days_%d" % act] = days_elapsed_in_act() + days
	days_elapsed += days
	if debt > 0.0:
		debt *= pow(1.0 + LOAN_RATE / 365.0, days)
	var st: Dictionary = result.stats
	trades += int(st.trades)
	wins += int(st.wins)
	stopouts += int(st.stopouts)
	# 首次强平返还（局外）
	if int(st.stopouts) > 0 and Save.meta_level("insurance1") > 0 and not used_specials.has("refund"):
		used_specials["refund"] = true
		var refund := maxf(0.0, before - money) * 0.3
		money += refund
	# FP
	var ret := profit / maxf(1.0, before)
	var base := {"trade": 15, "elite": 30, "boss": 50}.get(n.type, 15) as int
	var goal_hit := ret >= float(a.goal_pct)
	var gained := float(base) + clampf(ret * 100.0, 0.0, 25.0) + (15.0 if goal_hit and n.type == "trade" else 0.0) + float(extra.get("affi_fp", 0))
	gained *= mods.get_v("fp_mult")
	fp += int(gained)
	temp_mods.clear()
	rebuild_mods()
	max_net = maxf(max_net, net())
	var out := {"profit": profit, "fp": int(gained), "goal_hit": goal_hit, "ret": ret}
	if n.type == "boss":
		out.passed = net() >= target()
	return out

# ================================================================ 奖励/商店

func relic_pool(filter := "") -> Array:
	var out: Array = []
	for r in DB.get_json("res://data/run/relics.json").relics:
		if relics.has(r.id):
			continue
		if r.get("unlock", "") != "" and not Save.has_unlock(r.unlock):
			continue
		match filter:
			"info":
				if r.tag != "info": continue
			"risk":
				if r.tag != "risk": continue
			"chart":
				if not ["ma_chart", "bollinger", "rsi_gauge"].has(r.id): continue
			"rare":
				if r.rarity != "rare": continue
			"common":
				if r.rarity != "common": continue
		out.append(r)
	return out

func roll_relics(n: int, min_rarity := "") -> Array:
	var pool := relic_pool()
	var out: Array = []
	for i in n:
		if pool.is_empty():
			break
		var wsum := 0.0
		var ws: Array = []
		for r in pool:
			var w: float = {"common": 6.0, "uncommon": 3.0, "rare": 1.0}.get(r.rarity, 1.0)
			if min_rarity == "uncommon" and r.rarity == "common":
				w *= 0.2
			if min_rarity == "rare" and r.rarity != "rare":
				w *= 0.25
			ws.append(w)
			wsum += w
		var x := rng.randf() * wsum
		for k in pool.size():
			x -= ws[k]
			if x <= 0.0:
				out.append(pool[k])
				pool.remove_at(k)
				break
	return out

func add_relic(id: String) -> void:
	if not relics.has(id) and id != "":
		relics.append(id)
		Save.codex_add("relics", id)
		rebuild_mods()

func add_item(id: String) -> bool:
	if items.size() >= item_slots():
		return false
	items.append(id)
	Save.codex_add("items", id)
	return true

func add_curse(id: String) -> void:
	if not curses.has(id):
		curses.append(id)
		rebuild_mods()

func remove_curse(id := "") -> void:
	if curses.is_empty():
		return
	if id == "":
		id = curses[rng.randi() % curses.size()]
	curses.erase(id)
	rebuild_mods()

func price(base: int) -> int:
	return maxi(1, int(round(base * (1.0 - mods.get_v("shop_discount")))))

func relic_price(r: Dictionary) -> int:
	return price({"common": 55, "uncommon": 90, "rare": 150}.get(r.rarity, 80))

func gen_shop() -> Dictionary:
	var shop := {"relics": [], "items": [], "rerolls": 0}
	for r in roll_relics(3):
		shop.relics.append({"id": r.id, "price": relic_price(r), "sold": false})
	var its: Array = []
	for it in DB.get_json("res://data/run/items.json").items:
		if it.get("shop", true):
			its.append(it)
	its.shuffle()
	for k in mini(3 + (1 if Save.meta_level("shop1") > 0 else 0), its.size()):
		shop.items.append({"id": its[k].id, "price": price(int(its[k].price)), "sold": false})
	return shop

## 使用道具。返回提示文字
func use_item(idx: int) -> String:
	if idx < 0 or idx >= items.size():
		return ""
	var it := item_def(items[idx])
	var eff: Dictionary = it.get("effect", {})
	if eff.has("skip_node"):
		skip_next = true
	if eff.has("mental"):
		mental = clampf(mental + float(eff.mental), 0.0, mods.get_v("mental_max"))
	if eff.has("cure_tilt"):
		mental = maxf(mental, float(eff.cure_tilt))
	if eff.has("money_flat"):
		money += float(eff.money_flat)
	if eff.has("curse"):
		add_curse(eff.curse)
	if eff.has("loan_ratio"):
		var amt := money * float(eff.loan_ratio)
		money += amt
		debt += amt
	if eff.has("temp_mods"):
		for k in eff.temp_mods:
			temp_mods[k] = float(temp_mods.get(k, 0.0)) + float(eff.temp_mods[k]) if not String(k).ends_with("_mult") else float(eff.temp_mods[k])
		rebuild_mods()
	items.remove_at(idx)
	return "使用了「%s」" % it.get("name", "")

func repay(amount: float) -> float:
	var pay := minf(minf(amount, debt), money)
	money -= pay
	debt -= pay
	return pay

# ================================================================ 事件

## 结算事件选项效果，返回描述
func apply_effects(eff: Dictionary) -> String:
	var parts: Array = []
	if eff.has("gamble"):
		var g: Dictionary = eff.gamble
		var win := rng.randf() < float(g.chance)
		parts.append("【成功】" if win else "【失败】")
		parts.append(apply_effects(g.win if win else g.lose))
	if eff.has("mental"):
		mental = clampf(mental + float(eff.mental), 0.0, mods.get_v("mental_max"))
		parts.append("メンタル %+d" % int(eff.mental))
	if eff.has("fp"):
		fp = maxi(0, fp + int(eff.fp))
		parts.append("FP %+d" % int(eff.fp))
	if eff.has("money_act"):
		var m := act_money_base() * float(eff.money_act) * mods.get_v("work_pay_mult")
		money += m
		parts.append("资金 %s" % GameDate.yen(m, true))
	if eff.has("money_pct"):
		var m2 := money * float(eff.money_pct)
		money = maxf(0.0, money + m2)
		parts.append("资金 %s" % GameDate.yen(m2, true))
	if eff.has("loan_pct"):
		var l := money * float(eff.loan_pct)
		money += l
		debt += l
		parts.append("借入 %s（年利109.5%%）" % GameDate.yen(l))
	if eff.has("relic"):
		var rid: String = eff.relic
		var pick: Array = []
		match rid:
			"random": pick = roll_relics(1)
			"random_info": pick = relic_pool("info"); pick.shuffle()
			"random_risk": pick = relic_pool("risk"); pick.shuffle()
			"random_chart": pick = relic_pool("chart"); pick.shuffle()
			"random_rare": pick = relic_pool("rare"); pick.shuffle()
			_: pick = [relic_def(rid)]
		if not pick.is_empty() and not pick[0].is_empty():
			add_relic(pick[0].id)
			parts.append("获得手法「%s」" % pick[0].name)
		else:
			fp += 20
			parts.append("（没有可获得的手法，改为 FP +20）")
	if eff.has("item"):
		var iid: String = eff.item
		if add_item(iid):
			parts.append("获得道具「%s」" % item_def(iid).get("name", iid))
		else:
			parts.append("道具栏满了")
	if eff.has("curse"):
		add_curse(eff.curse)
		parts.append("获得诅咒「%s」" % curse_def(eff.curse).get("name", eff.curse))
	if eff.has("remove_curse") and not curses.is_empty():
		var c: String = curses[0]
		remove_curse(c)
		parts.append("移除了「%s」" % curse_def(c).get("name", c))
	return "，".join(parts.filter(func(s): return s != ""))

# ================================================================ 结束

func check_fail() -> String:
	if mental <= 0.0:
		return "broken"
	if money < 10000.0:
		return "bankrupt"
	return ""

func meta_points() -> int:
	var acts_cleared := act - 1 + (1 if victory else 0)
	var pts := 8.0 + nodes_cleared * 2.0 + acts_cleared * 25.0
	pts += maxf(0.0, log(maxf(max_net, 1.0) / start_money) / log(2.0)) * 6.0
	if victory:
		pts += 40.0 + ascension * 10.0
	return int(pts)

func log_add(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 60:
		log_lines.pop_front()

# ================================================================ 存档

const SAVE_KEYS := ["seed_value", "act", "layer", "map", "current", "money", "start_money", "debt", "fp", "mental",
	"broker_id", "friends", "relics", "items", "curses", "temp_mods", "skip_next", "ascension", "days_elapsed",
	"nodes_cleared", "max_net", "trades", "wins", "stopouts", "bosses_beaten", "used_specials", "friend_charges",
	"log_lines", "ended", "victory", "end_reason", "in_node", "shop_cache", "credit_given_act"]

func to_dict() -> Dictionary:
	var d := {"rng_state": rng.state}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d

static func from_dict(d: Dictionary) -> RunState:
	var r := RunState.new()
	for k in SAVE_KEYS:
		if d.has(k):
			var v = d[k]
			if typeof(r.get(k)) == TYPE_INT:
				v = int(v)
			r.set(k, v)
	r.rng.seed = r.seed_value
	if d.has("rng_state"):
		r.rng.state = int(d.rng_state)
	r.rebuild_mods()
	return r

func save() -> void:
	Save.data.run = to_dict()
	Save.write()

## 新一幕
func next_act() -> void:
	act += 1
	_gen_map()
	if ascension >= 9:
		add_curse("greed")
