class_name MarketSim
extends RefCounted
## 多因子行情引擎。
##
## 每个货币/资产是一个「单元」，有自己的对数强度 x（自身部分）；
## 有效强度 = x + Σ β·因子。品种价格 = anchor 比 × exp(有效强度差 + 品种偏移)。
## 一个 tick = 游戏内 15 分钟；一天 96 tick，从东京时间 07:00（纽约收盘）开始。
## 所有随机数来自同一个种子，可复现。

signal peg_broken(symbol: String)
signal intervention(unit: String, direction: int)

const TICKS_PER_DAY := 96
const DAY_START_HOUR := 7

## 东京时间每小时的流动性/波动倍率（index = 小时）。平均约 1。
const HOUR_VOL := [
	0.80, 0.70, 0.60, 0.55, 0.50, 0.55, 0.45, 0.55, # 00-07（纽约尾盘 → 换日）
	0.80, 1.00, 0.95, 0.85, 0.75, 0.80, 0.85, 1.05, # 08-15 东京
	1.25, 1.30, 1.20, 1.15, 1.20, 1.55, 1.60, 1.40, # 16-23 伦敦 / 纽约开盘
]
## 每小时点差倍率
const HOUR_SPREAD := [
	1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 3.0, 2.0,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
	1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0,
]

class Unit:
	var code: String
	var name: String
	var anchor_jpy: float
	var x := 0.0
	var fair := 0.0
	var vol: float
	var var_mult := 1.0
	var betas := {}
	var rate: float
	var carry: float
	var mr: float
	var trend: float
	var regime := 0 # 0 震荡 1 多头 2 空头
	var regime_left := 0
	var regime_forced_until := -1
	var jump_rate: float
	var jump: float
	# 每 tick 由事件效果重算
	var ev_drift := 0.0
	var ev_vol := 1.0
	var ev_jump := 1.0

class Factor:
	var id: String
	var name: String
	var v := 0.0
	var theta: float
	var vol: float
	var ev_drift := 0.0
	var ev_vol := 1.0

class Instrument:
	var symbol: String
	var name: String
	var base: String
	var quote: String
	var kind: String
	var digits: int
	var pip: float
	var spread_pips: float
	var contract: float
	var unlock: String
	var anchor_ratio: float
	var offset := 0.0
	var ev_spread := 1.0
	var spread_now := 0.0 # 当前点差（价格单位）
	var o := PackedFloat64Array()
	var h := PackedFloat64Array()
	var l := PackedFloat64Array()
	var c := PackedFloat64Array()
	var mid := 0.0
	var long_ratio := 0.5
	var peg := {} # {"floor": 1.2, "pressure": 0.0} 价格不得低于 floor
	var cap := {} # {"ceil": x} 价格不得高于 ceil
	var guide := {} # {"tick": 目标tick, "price": 目标价}
	var hunts := 0
	var halted := false

	func bid() -> float:
		return mid - spread_now * 0.5

	func ask() -> float:
		return mid + spread_now * 0.5

	func last_close(back := 0) -> float:
		var n := c.size()
		if n == 0:
			return mid
		return c[maxi(0, n - 1 - back)]

class Effect:
	var target: String   # 单元代码 / "factor:risk" / "pair:USDJPY"
	var channel: String  # level / drift / vol / jump / spread / regime / fair
	var magnitude: float
	var start: int
	var ramp: int
	var duration: int
	var fade: float
	var applied := 0.0
	var tag := ""

	func active_window(t: int) -> bool:
		return t >= start and t <= start + ramp + duration

var rng := RandomNumberGenerator.new()
var tick := 0 # 绝对 tick（从模拟开始）
var units := {}       # code -> Unit
var unit_order: Array[String] = []
var factors := {}     # id -> Factor
var instruments := {} # symbol -> Instrument
var symbol_order: Array[String] = []
var effects: Array[Effect] = []

## 难度/幕参数（RunState 或剧情脚本设置）
var params := {
	"vol_mult": 1.0,        # 整体波动
	"trend_mult": 1.0,      # 趋势强度
	"regime_days": 2.5,     # regime 平均持续天数
	"range_bias": 0.45,     # 切换时落入震荡的概率
	"jump_mult": 1.0,       # 自发跳跃频率
	"hunt_prob": 0.010,     # 每 tick 猎杀止损概率（价格接近止损簇时）
	"crowd_noise": 0.02,
	"spread_mult": 1.0,
	"fair_drift": 0.0015,   # 公允价值日漂移
	"intervention": true,   # 是否启用日元干预
}

var _intervention_cooldown := 0

func _init(seed_value: int = 0) -> void:
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())

# ---------------------------------------------------------------- 建立

func setup(units_data: Dictionary, instruments_data: Dictionary, overrides := {}) -> void:
	units.clear()
	unit_order.clear()
	factors.clear()
	instruments.clear()
	symbol_order.clear()
	effects.clear()
	for k in overrides.get("params", {}):
		params[k] = overrides.params[k]
	for d in units_data.get("units", []):
		var u := Unit.new()
		u.code = d.code
		u.name = d.name
		u.anchor_jpy = float(d.anchor_jpy)
		u.vol = float(d.vol)
		u.betas = d.get("betas", {})
		u.rate = float(d.get("rate", 0.0))
		u.carry = float(d.get("carry", 0.0))
		u.mr = float(d.get("mr", 0.02))
		u.trend = float(d.get("trend", 0.3))
		u.jump_rate = float(d.get("jump_rate", 0.02))
		u.jump = float(d.get("jump", 0.005))
		u.regime_left = _new_regime_len()
		var uo: Dictionary = overrides.get("units", {}).get(u.code, {})
		for k in uo:
			u.set(k, uo[k])
		units[u.code] = u
		unit_order.append(u.code)
	for d in units_data.get("factors", []):
		var f := Factor.new()
		f.id = d.id
		f.name = d.name
		f.theta = float(d.theta)
		f.vol = float(d.vol)
		factors[f.id] = f
	for d in instruments_data.get("instruments", []):
		var ins := Instrument.new()
		ins.symbol = d.symbol
		ins.name = d.name
		ins.base = d.base
		ins.quote = d.quote
		ins.kind = d.kind
		ins.digits = int(d.digits)
		ins.pip = float(d.pip)
		ins.spread_pips = float(d.spread)
		ins.contract = float(d.contract)
		ins.unlock = d.get("unlock", "")
		ins.anchor_ratio = units[ins.base].anchor_jpy / units[ins.quote].anchor_jpy
		instruments[ins.symbol] = ins
		symbol_order.append(ins.symbol)
	# 起始价格可覆盖：{"start_prices": {"USDJPY": 118.5}}
	var sp: Dictionary = overrides.get("start_prices", {})
	for sym in sp:
		if instruments.has(sym):
			var ins2: Instrument = instruments[sym]
			ins2.offset = log(float(sp[sym]) / _raw_price(ins2))
	for sym in overrides.get("pegs", {}):
		instruments[sym].peg = {"floor": float(overrides.pegs[sym]), "pressure": 0.0}
	for sym in symbol_order:
		var ins3: Instrument = instruments[sym]
		ins3.mid = price_of(ins3)
		ins3.spread_now = ins3.spread_pips * ins3.pip

func _new_regime_len() -> int:
	var days: float = params.regime_days * (0.5 + rng.randf())
	return maxi(8, int(days * TICKS_PER_DAY))

# ---------------------------------------------------------------- 价格

func eff_x(u: Unit) -> float:
	var v := u.x
	for fid in u.betas:
		if factors.has(fid):
			v += float(u.betas[fid]) * factors[fid].v
	return v

func _raw_price(ins: Instrument) -> float:
	return ins.anchor_ratio * exp(eff_x(units[ins.base]) - eff_x(units[ins.quote]))

func price_of(ins: Instrument) -> float:
	return _raw_price(ins) * exp(ins.offset)

func get_ins(symbol: String) -> Instrument:
	return instruments.get(symbol)

## 把 1 单位 code 货币换算成日元（用当前中间价）
func jpy_value(code: String) -> float:
	if code == "JPY":
		return 1.0
	return units[code].anchor_jpy * exp(eff_x(units[code]) - eff_x(units["JPY"]))

## 品种每日波动（价格比例），用于 UI 和 AI 估计
func daily_vol(ins: Instrument) -> float:
	var a: Unit = units[ins.base]
	var b: Unit = units[ins.quote]
	return sqrt(a.vol * a.vol * a.var_mult + b.vol * b.vol * b.var_mult) * params.vol_mult

# ---------------------------------------------------------------- 时间

func day_index() -> int:
	return tick / TICKS_PER_DAY

func tick_of_day() -> int:
	return tick % TICKS_PER_DAY

## 东京时间（小时, 分钟）
func clock() -> Vector2i:
	var minutes := DAY_START_HOUR * 60 + tick_of_day() * 15
	minutes %= 24 * 60
	return Vector2i(minutes / 60, minutes % 60)

func hour() -> int:
	return clock().x

# ---------------------------------------------------------------- 效果

func add_effect(target: String, channel: String, magnitude: float, delay := 0, ramp := 1, duration := 0, fade := 0.0, tag := "") -> Effect:
	var e := Effect.new()
	e.target = target
	e.channel = channel
	e.magnitude = magnitude
	e.start = tick + delay
	e.ramp = maxi(1, ramp)
	e.duration = maxi(0, duration)
	e.fade = fade
	e.tag = tag
	effects.append(e)
	return e

func remove_effects_tagged(tag: String) -> void:
	effects = effects.filter(func(e: Effect) -> bool: return e.tag != tag)

## 价格 level 冲击的目标累计值
func _level_target(e: Effect, t: int) -> float:
	if t < e.start:
		return 0.0
	var r := clampf(float(t - e.start + 1) / e.ramp, 0.0, 1.0)
	r = r * r * (3.0 - 2.0 * r)
	var f := 0.0
	if e.duration > 0:
		f = clampf(float(t - e.start - e.ramp) / e.duration, 0.0, 1.0)
	return e.magnitude * r * (1.0 - e.fade * f)

func _apply_level(target: String, delta: float) -> void:
	if target.begins_with("factor:"):
		var f: Factor = factors.get(target.substr(7))
		if f:
			f.v += delta
	elif target.begins_with("pair:"):
		var ins: Instrument = instruments.get(target.substr(5))
		if ins:
			ins.offset += delta
	elif units.has(target):
		units[target].x += delta

func _collect_effects() -> void:
	for code in unit_order:
		var u: Unit = units[code]
		u.ev_drift = 0.0
		u.ev_vol = 1.0
		u.ev_jump = 1.0
	for fid in factors:
		factors[fid].ev_drift = 0.0
		factors[fid].ev_vol = 1.0
	for sym in symbol_order:
		instruments[sym].ev_spread = 1.0
	var keep: Array[Effect] = []
	for e in effects:
		if tick > e.start + e.ramp + e.duration + 1:
			continue
		keep.append(e)
		if tick < e.start:
			continue
		match e.channel:
			"level":
				var want := _level_target(e, tick)
				_apply_level(e.target, want - e.applied)
				e.applied = want
			"drift":
				# magnitude = 每日对数漂移
				var per_tick := e.magnitude / TICKS_PER_DAY
				if e.target.begins_with("factor:"):
					var f: Factor = factors.get(e.target.substr(7))
					if f: f.ev_drift += per_tick
				elif e.target.begins_with("pair:"):
					var ins: Instrument = instruments.get(e.target.substr(5))
					if ins: ins.offset += per_tick
				elif units.has(e.target):
					units[e.target].ev_drift += per_tick
			"vol":
				if e.target == "*":
					for code in unit_order:
						units[code].ev_vol *= e.magnitude
				elif e.target.begins_with("factor:"):
					var f2: Factor = factors.get(e.target.substr(7))
					if f2: f2.ev_vol *= e.magnitude
				elif units.has(e.target):
					units[e.target].ev_vol *= e.magnitude
			"jump":
				if units.has(e.target):
					units[e.target].ev_jump *= e.magnitude
			"spread":
				if e.target == "*":
					for sym in symbol_order:
						instruments[sym].ev_spread *= e.magnitude
				elif e.target.begins_with("pair:"):
					var ins2: Instrument = instruments.get(e.target.substr(5))
					if ins2: ins2.ev_spread *= e.magnitude
				else:
					for sym in symbol_order:
						var ins3: Instrument = instruments[sym]
						if ins3.base == e.target or ins3.quote == e.target:
							ins3.ev_spread *= e.magnitude
			"regime":
				if units.has(e.target) and tick == e.start:
					var u2: Unit = units[e.target]
					u2.regime = int(e.magnitude)
					u2.regime_forced_until = e.start + e.ramp + e.duration
					u2.regime_left = e.ramp + e.duration
			"fair":
				if units.has(e.target) and tick == e.start:
					units[e.target].fair += e.magnitude
	effects = keep

# ---------------------------------------------------------------- 推进

## 推进一个 tick。返回 true 表示本 tick 是新一天的第一个 tick。
func step() -> void:
	var hr := hour()
	var vol_profile: float = HOUR_VOL[hr]
	var spread_profile: float = HOUR_SPREAD[hr]
	var sq := sqrt(1.0 / TICKS_PER_DAY)

	# 记录开盘前价格
	var prev := {}
	for sym in symbol_order:
		prev[sym] = instruments[sym].mid

	# 1) 事件效果（level 冲击在开盘瞬间生效 → 形成跳空）
	_collect_effects()

	# 自发跳跃（也在开盘瞬间）
	for code in unit_order:
		var u: Unit = units[code]
		var lam: float = u.jump_rate * params.jump_mult * u.ev_jump / TICKS_PER_DAY * vol_profile
		if rng.randf() < lam:
			u.x += rng.randfn(0.0, u.jump * params.vol_mult)

	# 剧情引导（布朗桥）
	for sym in symbol_order:
		var ins: Instrument = instruments[sym]
		if ins.guide.is_empty():
			continue
		var remain: int = int(ins.guide.tick) - tick
		if remain <= 0:
			ins.offset += log(float(ins.guide.price) / price_of(ins))
			ins.guide = {}
		else:
			ins.offset += log(float(ins.guide.price) / price_of(ins)) / float(remain + 1)

	_enforce_pegs()
	var opens := {}
	for sym in symbol_order:
		opens[sym] = price_of(instruments[sym])

	# 2) 扩散：因子
	for fid in factors:
		var f: Factor = factors[fid]
		var dv := -f.theta * f.v / TICKS_PER_DAY + f.ev_drift
		dv += rng.randfn(0.0, 1.0) * f.vol * f.ev_vol * sq * vol_profile * params.vol_mult
		f.v += dv

	# 3) 扩散：单元
	for code in unit_order:
		var u: Unit = units[code]
		_update_regime(u)
		var trend_drift := 0.0
		if u.regime == 1:
			trend_drift = u.trend * u.vol * params.trend_mult
		elif u.regime == 2:
			trend_drift = -u.trend * u.vol * params.trend_mult
		u.fair += rng.randfn(0.0, params.fair_drift) * sq
		var drift := (trend_drift + u.carry + u.mr * (u.fair - u.x)) / TICKS_PER_DAY + u.ev_drift
		var sigma: float = u.vol * sqrt(u.var_mult) * params.vol_mult * u.ev_vol * vol_profile * sq
		var z := rng.randfn(0.0, 1.0)
		u.x += drift + sigma * z
		# GARCH 式波动聚集（var_mult 均值约 1）
		u.var_mult = clampf(0.004 + 0.035 * z * z + 0.961 * u.var_mult, 0.35, 6.0)

	_enforce_pegs()
	_maybe_intervene()

	# 4) 写入 OHLC、点差、散户、猎杀止损
	for sym in symbol_order:
		var ins: Instrument = instruments[sym]
		var op: float = opens[sym]
		var cl := price_of(ins)
		var tick_sig := daily_vol(ins) * sq * vol_profile * cl
		var hi := maxf(op, cl) + absf(rng.randfn(0.0, tick_sig * 0.45))
		var lo := minf(op, cl) - absf(rng.randfn(0.0, tick_sig * 0.45))
		# 跳空时，前收盘到开盘之间没有成交（不填补）
		if not ins.peg.is_empty():
			lo = maxf(lo, float(ins.peg.floor) * 0.99995)
		ins.o.append(op)
		ins.h.append(hi)
		ins.l.append(lo)
		ins.c.append(cl)
		ins.mid = cl
		var vol_widen := clampf(sqrt(units[ins.base].var_mult * units[ins.quote].var_mult), 1.0, 3.0)
		ins.spread_now = ins.spread_pips * ins.pip * spread_profile * ins.ev_spread * params.spread_mult * vol_widen
		_update_crowd(ins, float(prev[sym]), cl, tick_sig)

	tick += 1

func _update_regime(u: Unit) -> void:
	if u.regime_forced_until >= tick:
		return
	u.regime_left -= 1
	if u.regime_left > 0:
		return
	if rng.randf() < params.range_bias:
		u.regime = 0
	else:
		u.regime = 1 if rng.randf() < 0.5 else 2
	u.regime_left = _new_regime_len()

func _enforce_pegs() -> void:
	for sym in symbol_order:
		var ins: Instrument = instruments[sym]
		if not ins.peg.is_empty():
			var p := price_of(ins)
			var fl: float = ins.peg.floor
			if p < fl:
				# 央行卖出报价货币（如卖瑞郎买欧元），把报价货币自身强度压低
				var need := log(fl / p) + rng.randf() * 0.00008
				units[ins.quote].x -= need
				ins.peg.pressure = float(ins.peg.pressure) + need
		if not ins.cap.is_empty():
			var p2 := price_of(ins)
			var ce: float = ins.cap.ceil
			if p2 > ce:
				units[ins.base].x -= log(p2 / ce) + rng.randf() * 0.00008

## 钉住撤销：把这些年被央行“压住”的强度一次性释放（magnitude 可覆盖）
func break_peg(symbol: String, magnitude := -1.0, overshoot := 0.5, recover_ticks := 24) -> void:
	var ins: Instrument = instruments.get(symbol)
	if ins == null or ins.peg.is_empty():
		return
	var released: float = magnitude if magnitude > 0.0 else clampf(float(ins.peg.pressure) * 0.6, 0.08, 0.35)
	ins.peg = {}
	# 先超调到 released*(1+overshoot)，再回吐 overshoot 部分
	var total := released * (1.0 + overshoot)
	add_effect(ins.quote, "level", total, 0, 2, recover_ticks, overshoot / (1.0 + overshoot), "peg_break")
	add_effect("pair:" + symbol, "spread", 60.0, 0, 1, 6, 0.0, "peg_break")
	add_effect("*", "spread", 4.0, 0, 1, 12, 0.0, "peg_break")
	add_effect(ins.quote, "vol", 3.0, 0, 1, TICKS_PER_DAY * 2, 0.0, "peg_break")
	peg_broken.emit(symbol)

func _maybe_intervene() -> void:
	if not params.intervention:
		return
	if _intervention_cooldown > 0:
		_intervention_cooldown -= 1
		return
	var uj: Instrument = instruments.get("USDJPY")
	if uj == null or uj.c.size() < TICKS_PER_DAY * 3:
		return
	var now := price_of(uj)
	var ago := uj.c[uj.c.size() - TICKS_PER_DAY * 3]
	var chg := log(now / ago)
	# 三天内日元升值超 4% → 有概率出手卖日元
	if chg < -0.04 and rng.randf() < 0.02:
		add_effect("JPY", "level", -0.025, 0, 3, TICKS_PER_DAY, 0.45, "intervention")
		add_effect("*", "spread", 3.0, 0, 1, 8)
		_intervention_cooldown = TICKS_PER_DAY * 5
		intervention.emit("JPY", -1)
	elif chg > 0.045 and rng.randf() < 0.02:
		add_effect("JPY", "level", 0.022, 0, 3, TICKS_PER_DAY, 0.5, "intervention")
		add_effect("*", "spread", 3.0, 0, 1, 8)
		_intervention_cooldown = TICKS_PER_DAY * 5
		intervention.emit("JPY", 1)

## 散户（逆张り倾向）与止损簇
func _update_crowd(ins: Instrument, prev_price: float, now: float, tick_sig: float) -> void:
	if tick_sig <= 0.0:
		return
	var ret := (now - prev_price) / tick_sig
	ins.long_ratio = clampf(ins.long_ratio - 0.004 * ret + 0.01 * (0.5 - ins.long_ratio) + rng.randfn(0.0, params.crowd_noise) * 0.1, 0.08, 0.92)
	if ins.halted or ins.c.size() < TICKS_PER_DAY:
		return
	var cl := stop_clusters(ins)
	var day_sig := daily_vol(ins) * now
	for k in cl:
		var lvl: float = cl[k]
		var dist := absf(now - lvl)
		if dist < day_sig * 0.25 and rng.randf() < params.hunt_prob:
			var through := dist + day_sig * rng.randf_range(0.08, 0.2)
			var dir := 1.0 if lvl > now else -1.0
			var target_price := maxf(now + dir * through, now * 0.5)
			add_effect("pair:" + ins.symbol, "level", log(target_price / now), 0, 2, 8, 0.85, "hunt")
			ins.hunts += 1
			break

## 止损簇位置：近 2 日高点上方（空单止损）与低点下方（多单止损）
func stop_clusters(ins: Instrument) -> Dictionary:
	var n := ins.h.size()
	if n < 8:
		return {}
	var from := maxi(0, n - TICKS_PER_DAY * 2)
	var hi := -INF
	var lo := INF
	for i in range(from, n):
		hi = maxf(hi, ins.h[i])
		lo = minf(lo, ins.l[i])
	var pad := daily_vol(ins) * ins.mid * 0.05
	return {"short_stops": hi + pad, "long_stops": lo - pad}

# ---------------------------------------------------------------- 工具

## 先空跑若干天，让图表有历史（不触发任何事件）
func warmup(days: int) -> void:
	var saved_int: bool = params.intervention
	params.intervention = false
	for i in days * TICKS_PER_DAY:
		step()
	params.intervention = saved_int

## 设置剧情引导：在 ticks_from_now 个 tick 后让价格到达 price
func guide_to(symbol: String, price: float, ticks_from_now: int) -> void:
	var ins: Instrument = instruments.get(symbol)
	if ins:
		ins.guide = {"tick": tick + maxi(1, ticks_from_now), "price": price}

func regime_name(code: String) -> String:
	var u: Unit = units.get(code)
	if u == null:
		return ""
	return ["震荡", "上升", "下跌"][u.regime]

## 公允价值（价格）：剔除短期噪音后的“合理价位”，给萌智子的能力用
func fair_price(ins: Instrument) -> float:
	var a: Unit = units[ins.base]
	var b: Unit = units[ins.quote]
	var fa := a.fair
	var fb := b.fair
	for fid in a.betas:
		if factors.has(fid): fa += float(a.betas[fid]) * factors[fid].v * 0.5
	for fid in b.betas:
		if factors.has(fid): fb += float(b.betas[fid]) * factors[fid].v * 0.5
	return ins.anchor_ratio * exp(fa - fb + ins.offset)

## 聚合 K 线：tf = 每根包含的 tick 数；返回最近 count 根 [o,h,l,c] 的数组
func candles(symbol: String, tf: int, count: int) -> Array:
	var ins: Instrument = instruments.get(symbol)
	var out: Array = []
	if ins == null:
		return out
	var n := ins.c.size()
	if n == 0:
		return out
	# 按绝对 tick 对齐：最后一根可能未走完
	var first_tick := tick - n
	var last_bucket := (tick - 1) / tf
	var first_bucket := maxi(last_bucket - count + 1, first_tick / tf)
	for b in range(first_bucket, last_bucket + 1):
		var s := maxi(b * tf - first_tick, 0)
		var e := mini((b + 1) * tf - first_tick, n)
		if e <= s:
			continue
		var hi := -INF
		var lo := INF
		for i in range(s, e):
			hi = maxf(hi, ins.h[i])
			lo = minf(lo, ins.l[i])
		out.append([ins.o[s], hi, lo, ins.c[e - 1], b * tf])
	return out

static func fmt(p: float, digits: int) -> String:
	if digits <= 0:
		return str(int(round(p)))
	return ("%." + str(digits) + "f") % p

func format_price(ins: Instrument, p: float) -> String:
	return fmt(p, ins.digits)
