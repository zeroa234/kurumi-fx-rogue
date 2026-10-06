class_name EventEngine
extends RefCounted
## 事件引擎：经济日历（预定指标）、随机新闻/灾害/谣言、剧情脚本事件、SNS 时间线。
## 每 tick 在 market.step() 之前调用 update()。

signal news_posted(item: Dictionary)
signal indicator_released(item: Dictionary)
signal calendar_updated
signal sns_posted(item: Dictionary)

const PIPE := 2 # 事件被“决定”到真正影响价格之间的 tick 数

var market: MarketSim
var mods: Mods
var rng := RandomNumberGenerator.new()
var indicators: Array = []
var news_templates: Array = []
var sns_data := {}
var calendar: Array[Dictionary] = []   # 预定指标（含已发布）
var pending: Array[Dictionary] = []    # 待发布的新闻标题 {tick, item}
var scripted: Array[Dictionary] = []   # 剧情/Boss 定时事件 {tick, def}
var news_log: Array[Dictionary] = []
var sns_log: Array[Dictionary] = []
var weekday_fn: Callable               # func(day_index) -> 1..5（周一..周五）
var act := 1
var random_news := true
var enable_sns := true
var affi_enabled := false
var last_news_tick := -999
var _sns_cd := 4

## 每幕参数
var params := {
	"news_per_day": 2.0,
	"disaster_mult": 1.0,
	"rumor_mult": 1.0,
	"indicator_mult": 1.0,
	"min_indicators_week": 2,
	"news_scale": 1.0,
}

func _init(m: MarketSim, md: Mods, seed_value: int) -> void:
	market = m
	mods = md
	rng.seed = seed_value ^ 0xe7e7
	var ind: Dictionary = DB.get_json("res://data/events/indicators.json")
	indicators = ind.get("indicators", [])
	news_templates = DB.get_json("res://data/events/news.json").get("news", [])
	sns_data = DB.get_json("res://data/events/sns.json")

# ---------------------------------------------------------------- 日历

## 东京时间 → 交易日内 tick（交易日从 07:00 开始）
static func tick_in_day(hour: int, minute: int) -> int:
	var h := (hour - MarketSim.DAY_START_HOUR + 24) % 24
	return h * 4 + minute / 15

## 为从 first_day 开始的 n_days 个交易日排日历
func schedule_days(first_day: int, n_days: int) -> void:
	var count := 0
	var candidates: Array = []
	for d in range(first_day, first_day + n_days):
		var wd: int = weekday_fn.call(d) if weekday_fn.is_valid() else (d % 5) + 1
		for ind in indicators:
			var iwd: int = int(ind.weekday)
			# 07:00 以前发布的指标属于前一个交易日
			if int(ind.hour) < MarketSim.DAY_START_HOUR:
				iwd -= 1
			if iwd != wd:
				continue
			candidates.append([d, ind])
			if rng.randf() < float(ind.chance) * params.indicator_mult:
				_add_indicator(d, ind)
				count += 1
	var need: int = int(ceil(params.min_indicators_week * n_days / 5.0))
	candidates.shuffle()
	for c in candidates:
		if count >= need:
			break
		if _already(c[0], c[1].id):
			continue
		_add_indicator(c[0], c[1])
		count += 1
	calendar.sort_custom(func(a, b): return a.tick < b.tick)
	calendar_updated.emit()

func _already(day: int, id: String) -> bool:
	for c in calendar:
		if c.day == day and c.id == id:
			return true
	return false

func _add_indicator(day: int, ind: Dictionary, forced := {}) -> Dictionary:
	var t := day * MarketSim.TICKS_PER_DAY + tick_in_day(int(ind.hour), int(ind.minute))
	if t <= market.tick:
		return {}
	var item := {
		"id": ind.id, "name": ind.name, "unit": ind.unit, "stars": int(ind.stars),
		"day": day, "tick": t, "released": false, "kind": ind.get("kind", "data"),
		"hour": int(ind.hour), "minute": int(ind.minute),
	}
	if item.kind == "rate":
		var u: MarketSim.Unit = market.units[ind.unit]
		var step: float = float(ind.step)
		var r := rng.randf()
		var exp_move := 0.0
		if r < 0.18:
			exp_move = step
		elif r < 0.33:
			exp_move = -step
		var actual_move := exp_move
		var s := rng.randf()
		if s < 0.12:
			actual_move = exp_move + step
		elif s < 0.24:
			actual_move = exp_move - step
		item.previous = u.rate
		item.forecast = u.rate + exp_move
		item.actual = u.rate + actual_move
		item.fmt = "%.2f%%"
		item.surprise = (actual_move - exp_move) / step
	else:
		var mean: float = float(ind.mean)
		var sd: float = float(ind.sd)
		item.previous = mean + rng.randfn(0.0, sd)
		item.forecast = mean + rng.randfn(0.0, sd * 0.8)
		item.actual = float(item.forecast) + rng.randfn(0.0, float(ind.surprise_sd))
		item.fmt = ind.fmt
		item.surprise = (float(item.actual) - float(item.forecast)) / float(ind.surprise_sd) * float(ind.good)
	for k in forced:
		item[k] = forced[k]
	# 只指定了惊喜值时，反推实际值，保持显示一致
	if forced.has("surprise") and not forced.has("actual"):
		if item.kind == "rate":
			item.actual = float(item.forecast) + float(forced.surprise) * float(ind.step)
		else:
			item.actual = float(item.forecast) + float(forced.surprise) * float(ind.surprise_sd) * float(ind.good)
	item.def = ind
	# 预测精度：给出“上振/下振”倾向提示，准确率随精度上升
	var acc: float = 0.5 + 0.45 * clampf(mods.get_v("forecast_acc"), 0.0, 1.0)
	var true_dir := signf(float(item.surprise))
	item.hint = int(true_dir if rng.randf() < acc else -true_dir)
	calendar.append(item)
	return item

## 剧情用：强制安排一个指标，forced 可指定 forecast/actual/surprise
func schedule_indicator(id: String, day: int, forced := {}) -> Dictionary:
	for ind in indicators:
		if ind.id == id:
			var it := _add_indicator(day, ind, forced)
			calendar.sort_custom(func(a, b): return a.tick < b.tick)
			calendar_updated.emit()
			return it
	return {}

func upcoming(within_ticks: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for c in calendar:
		if not c.released and c.tick >= market.tick and c.tick - market.tick <= within_ticks:
			out.append(c)
	return out

# ---------------------------------------------------------------- 每 tick

func update() -> void:
	var t := market.tick
	# 1) 指标发布
	for c in calendar:
		if c.released:
			continue
		if c.tick == t + 1:
			# 发布前一刻业者扩大点差
			market.add_effect(c.unit, "spread", 2.5, 0, 1, 1)
		if c.tick == t:
			_release(c)
	# 2) 剧情定时事件
	for s in scripted.duplicate():
		if int(s.tick) <= t:
			scripted.erase(s)
			fire(s.def)
	# 3) 随机事件
	if random_news:
		var lam: float = params.news_per_day / MarketSim.TICKS_PER_DAY
		if rng.randf() < lam:
			_random_news()
	# 4) 待发布标题
	for p in pending.duplicate():
		if int(p.tick) <= t:
			pending.erase(p)
			_post(p.item)
	# 5) SNS
	if enable_sns:
		_sns_cd -= 1
		if _sns_cd <= 0:
			_sns_cd = rng.randi_range(5, 12)
			_sns_tick()

func _release(c: Dictionary) -> void:
	c.released = true
	var def: Dictionary = c.def
	var z: float = clampf(float(c.surprise), -4.0, 4.0)
	var scale: float = params.news_scale
	if c.kind == "rate":
		var u: MarketSim.Unit = market.units[c.unit]
		u.rate = float(c.actual)
		var mag := float(def.sens) * z * scale
		market.add_effect(c.unit, "level", mag, 0, 2, 48, 0.25)
		if absf(z) >= 0.9:
			market.add_effect(c.unit, "regime", 1 if z > 0 else 2, 0, 1, MarketSim.TICKS_PER_DAY * 2)
		# 声明中的“前瞻指引”：没有意外时也有小幅漂移
		market.add_effect(c.unit, "drift", rng.randfn(0.0, 0.004), 0, 1, 48)
	else:
		var mag2 := float(def.sens) * z * scale
		market.add_effect(c.unit, "level", mag2, 0, 2, 24, 0.35)
	if absf(float(def.get("risk", 0.0))) > 0.0:
		market.add_effect("factor:risk", "level", float(def.risk) * z * 0.8, 0, 2, 48, 0.5)
	market.add_effect(c.unit, "vol", 1.0 + 0.5 * int(c.stars), 0, 1, 8)
	market.add_effect(c.unit, "spread", 1.5 + int(c.stars), 0, 1, 2)
	var actual_s: String = (c.fmt % float(c.actual)) if c.fmt != "" else str(c.actual)
	var fc_s: String = (c.fmt % float(c.forecast)) if c.fmt != "" else str(c.forecast)
	var verdict := "符合预期"
	if z > 0.6:
		verdict = "好于预期" if c.kind != "rate" else "鹰派意外"
	elif z < -0.6:
		verdict = "差于预期" if c.kind != "rate" else "鸽派意外"
	var item := {
		"tick": market.tick, "kind": "indicator", "icon": "calendar",
		"title": "%s：%s（预测 %s）%s" % [c.name, actual_s, fc_s, verdict],
		"body": "", "unit": c.unit, "severity": int(c.stars), "z": z,
	}
	last_news_tick = market.tick
	indicator_released.emit(c)
	_post(item)

func _random_news() -> void:
	var pool: Array = []
	var total := 0.0
	var hr := market.hour()
	for n in news_templates:
		if not n.get("acts", [1, 2, 3]).has(float(act)) and not n.get("acts", [1, 2, 3]).has(act):
			continue
		if n.get("early_morning", false) and not (hr >= 5 and hr <= 8):
			continue
		var w: float = float(n.get("weight", 1.0))
		match n.get("kind", ""):
			"disaster": w *= params.disaster_mult
			"rumor": w *= params.rumor_mult
		if w <= 0.0:
			continue
		pool.append([n, w])
		total += w
	if total <= 0.0:
		return
	var r := rng.randf() * total
	for p in pool:
		r -= p[1]
		if r <= 0.0:
			fire(p[0], true)
			return

## 触发一个事件模板（剧情/Boss 也调用）。randomize = 是否随机缩放强度、随机方向。
func fire(def: Dictionary, randomize := false) -> Dictionary:
	var cur := ""
	var pool: Array = def.get("pool", [])
	if not pool.is_empty():
		cur = pool[rng.randi() % pool.size()]
	var sgn := 1.0
	if def.get("sign", "") == "random":
		sgn = 1.0 if rng.randf() < 0.5 else -1.0
	var title: String = def.get("title", "")
	if def.has("title_up"):
		title = def.title_up if sgn > 0 else def.title_down
	var cname: String = market.units[cur].name if cur != "" and market.units.has(cur) else ""
	title = title.replace("$N", cname)
	var body: String = String(def.get("body", "")).replace("$N", cname)
	var is_rumor: bool = def.get("kind", "") == "rumor"
	var truth := true
	if is_rumor:
		truth = rng.randf() < float(def.get("credibility", 0.5))
	var scale: float = rng.randf_range(0.6, 1.4) if randomize else 1.0
	scale *= params.news_scale if randomize else 1.0
	var delay: int = int(def.get("delay", PIPE))
	for e in def.get("effects", []):
		var target: String = String(e.target).replace("$C", cur)
		if target == "" or (not target.begins_with("factor:") and not target.begins_with("pair:") and target != "*" and not market.units.has(target)):
			continue
		var ch: String = e.channel
		var mag: float = float(e.mag)
		if ch == "level" or ch == "drift":
			mag *= sgn * scale
		elif ch == "regime":
			if sgn < 0.0:
				mag = 3.0 - mag # 1<->2 互换
		var fade: float = float(e.get("fade", 0.0))
		var dur: int = int(e.get("dur", 0))
		if is_rumor and not truth and ch == "level":
			fade = 1.0
			dur = rng.randi_range(16, 48)
		market.add_effect(target, ch, mag, delay + int(e.get("delay", 0)), int(e.get("ramp", 1)), dur, fade, def.get("id", ""))
	if def.has("rate_change") and cur != "":
		market.units[cur].rate += float(def.rate_change)
	if def.has("peg_break"):
		var pb: Dictionary = def.peg_break
		market.break_peg(pb.symbol, float(pb.get("magnitude", -1.0)), float(pb.get("overshoot", 0.5)), int(pb.get("recover", 24)))
	var item := {
		"tick": market.tick, "kind": def.get("kind", "news"), "icon": def.get("icon", "paper"),
		"title": title, "body": body, "unit": cur, "region": def.get("region", ""),
		"severity": int(def.get("severity", 3 if def.get("kind", "") in ["disaster", "cb"] else 2)),
		"id": def.get("id", ""),
	}
	# 散户看到新闻的时间：比价格晚 1 tick，情报能力可以提前
	var lag: int = delay + 1 - int(mods.get_v("news_lead"))
	if def.get("instant", false):
		lag = 0
	lag = maxi(0, lag)
	if lag == 0:
		_post(item)
	else:
		pending.append({"tick": market.tick + lag, "item": item})
	last_news_tick = market.tick + delay
	if is_rumor and not truth and def.has("denial"):
		pending.append({"tick": market.tick + delay + int(def.get("effects", [{}])[0].get("ramp", 3)) + 2, "item": {
			"tick": 0, "kind": "denial", "icon": "paper",
			"title": String(def.denial).replace("$N", cname), "body": "", "unit": cur, "severity": 1,
		}})
	return item

## 剧情/Boss：在绝对 tick 安排一个事件定义
func schedule(tick_at: int, def: Dictionary) -> void:
	scripted.append({"tick": tick_at, "def": def})

func _post(item: Dictionary) -> void:
	item.tick = market.tick
	news_log.append(item)
	if news_log.size() > 200:
		news_log.pop_front()
	news_posted.emit(item)

## 直接发一条新闻文字（不影响价格）
func post_text(title: String, kind := "news", icon := "paper", severity := 1) -> void:
	_post({"tick": market.tick, "kind": kind, "icon": icon, "title": title, "body": "", "severity": severity})

# ---------------------------------------------------------------- SNS

func _sns_tick() -> void:
	var ctx: Dictionary = sns_data.get("contexts", {})
	var handles: Array = sns_data.get("handles", ["@anon"])
	var syms: Array = []
	for s in market.symbol_order:
		var ins: MarketSim.Instrument = market.instruments[s]
		if ins.c.size() > MarketSim.TICKS_PER_DAY:
			syms.append(s)
	if syms.is_empty():
		return
	var sym: String = syms[rng.randi() % syms.size()]
	var ins2: MarketSim.Instrument = market.instruments[sym]
	var n := ins2.c.size()
	var ret := log(ins2.c[n - 1] / ins2.c[n - 1 - mini(n - 1, 24)])
	var dv := market.daily_vol(ins2) * 0.5
	var key := "idle"
	if market.tick - last_news_tick <= 4 and market.tick >= last_news_tick:
		key = "event"
	elif ret > dv:
		key = "up_strong"
	elif ret < -dv:
		key = "down_strong"
	elif ins2.long_ratio > 0.7:
		key = "crowd_long"
	elif ins2.long_ratio < 0.3:
		key = "crowd_short"
	elif rng.randf() < 0.4:
		key = "range"
	var lines: Array = ctx.get(key, ctx.get("idle", []))
	if lines.is_empty():
		return
	var text: String = lines[rng.randi() % lines.size()]
	text = text.replace("{sym}", ins2.name).replace("{p}", market.format_price(ins2, ins2.mid))
	var who: String = handles[rng.randi() % handles.size()]
	if affi_enabled and rng.randf() < 0.12:
		var affi: Array = sns_data.get("affi", [])
		if not affi.is_empty():
			who = "@あふぃちゃん"
			text = affi[rng.randi() % affi.size()]
	var item := {"tick": market.tick, "who": who, "text": text, "ctx": key}
	sns_log.append(item)
	if sns_log.size() > 80:
		sns_log.pop_front()
	sns_posted.emit(item)

func post_sns(who: String, text: String) -> void:
	var item := {"tick": market.tick, "who": who, "text": text, "ctx": "script"}
	sns_log.append(item)
	sns_posted.emit(item)
