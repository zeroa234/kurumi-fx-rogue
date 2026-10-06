class_name Kurumi
extends RefCounted
## 久留美的心理状态：メンタル、暴走、立绘表情、台词。

signal mental_changed(value: float)
signal tilt_changed(on: bool)
signal said(text: String, face: String)
signal impulse(kind: String)

const TILT_LINE := 30.0

var mods: Mods
var mental := 80.0
var tilt := false
var face := "normal"
var _bark_cd := 0
var _impulse_cd := 48
var barks := {}
var rng := RandomNumberGenerator.new()

func _init(md: Mods, start_mental := 80.0, seed_value := 0) -> void:
	mods = md
	mental = start_mental
	rng.seed = seed_value ^ 0x6b75
	barks = DB.get_json("res://data/story/barks.json")

func mental_max() -> float:
	return mods.get_v("mental_max")

func change(delta: float) -> void:
	if delta < 0.0:
		delta *= mods.get_v("mental_loss_mult")
	else:
		delta *= mods.get_v("mental_gain_mult")
	mental = clampf(mental + delta, 0.0, mental_max())
	mental_changed.emit(mental)
	var t := mental < TILT_LINE - mods.get_v("tilt_resist")
	if t != tilt:
		tilt = t
		tilt_changed.emit(tilt)
		if tilt:
			say("tilt", true)

func is_broken() -> bool:
	return mental <= 0.0

func say(key: String, force := false) -> void:
	if not force and _bark_cd > 0:
		return
	var lines: Array = barks.get(key, [])
	if lines.is_empty():
		return
	var l: Dictionary = lines[rng.randi() % lines.size()]
	face = l.get("f", "normal")
	_bark_cd = 10
	said.emit(l.t, face)

func say_text(text: String, f := "normal") -> void:
	face = f
	_bark_cd = 12
	said.emit(text, f)

## 平仓后：亏损按占净值比例扣メンタル
func on_closed(pnl: float, equity_before: float, reason: String) -> void:
	var ratio := pnl / maxf(1.0, equity_before)
	if pnl >= 0.0:
		change(minf(8.0, 2.0 + ratio * 40.0))
		say("win_big" if ratio > 0.08 else "win_small", ratio > 0.08)
	else:
		change(maxf(-30.0, -1.5 + ratio * 70.0))
		say("loss_big" if ratio < -0.06 else "loss_small", ratio < -0.06)

func on_margin_call() -> void:
	change(-6.0)
	say("margin_call", true)

func on_stop_out() -> void:
	change(-22.0)
	say("stop_out", true)

## 每 tick：根据含み损益更新表情，偶尔说话；暴走时会冒出冲动
func on_tick(float_ratio: float, has_positions: bool) -> void:
	_bark_cd = maxi(0, _bark_cd - 1)
	if tilt:
		face = "tilt"
		_impulse_cd -= 1
		if _impulse_cd <= 0:
			_impulse_cd = rng.randi_range(36, 72)
			impulse.emit("nanpin" if has_positions else "all_in")
		return
	if not has_positions:
		face = "normal"
	elif float_ratio > 0.1:
		face = "smug"
	elif float_ratio > 0.02:
		face = "happy"
	elif float_ratio < -0.1:
		face = "shock"
	elif float_ratio < -0.02:
		face = "worried"
	else:
		face = "focus"
	if _bark_cd == 0 and rng.randf() < 0.01:
		if float_ratio > 0.03:
			say("float_up")
		elif float_ratio < -0.03:
			say("float_down")
		else:
			say("idle")

func daily_regen() -> void:
	var r := 2.0 + mods.get_v("mental_regen")
	if r != 0.0:
		change(r)
