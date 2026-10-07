extends Control
## 肉鸽交易节点：普通相場 / 精英 / Boss。结算后回到地图。

var run: RunState
var node: Dictionary
var session: TradeSession
var screen: TradeScreen
var extra := {"loan": 0.0, "affi_fp": 0}
var _charges := {}
var _cold_eye_until := -1
var _had_position_today := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	run = Game.run
	if run == null:
		Game.goto("res://src/run/run_hub.tscn")
		return
	node = run.node(Game.params.get("node", run.current))
	var cfg := run.trade_config(node)
	session = TradeSession.new(cfg, run.mods)
	screen = TradeScreen.new(session)
	_setup_bgm()
	add_child(screen)
	screen._set_speed(0, true)
	screen.session_done.connect(_on_done)
	session.day_changed.connect(_on_day)
	session.ticked.connect(_on_tick)
	session.account.opened.connect(func(_p): _had_position_today = true)
	_add_friend_buttons()
	_intro()

## 按节点类型选曲（docs/bgm.md §3）；第 3 幕及无尽模式的 Boss 用 boss_final；带下限的 Boss（黑色星期四）撤销后换 snb_shock
func _setup_bgm() -> void:
	match String(node.type):
		"elite": Bgm.play("trade_elite")
		"boss": Bgm.play("boss_final" if run.act >= 3 else "boss")
		_: Bgm.play("trade_main")
	if node.type == "boss":
		screen.bgm_peg_break = "snb_shock"

## Game.back()：返回键 / 弹窗中的 Esc → 交易画面的暂停菜单
func _on_back() -> bool:
	return screen != null and screen.on_back()

func _intro() -> void:
	var lines: Array = []
	var a := run.act_def()
	match String(node.type):
		"trade":
			lines.append({"who": "kurumi", "face": "focus", "text": "接下来 %d 个交易日。目标：资金 +%d%%（达成有额外 FP）。" % [int(a.days_trade), int(float(a.goal_pct) * 100)]})
		"elite":
			var e := run.elite_def(node.get("elite", ""))
			lines.append({"who": "narrator", "text": "【精英】%s —— %s" % [e.get("name", ""), e.get("desc", "")]})
		"boss":
			var b := run.boss_def(node.get("boss", ""))
			lines.append({"who": "narrator", "text": "【BOSS】%s —— %s" % [b.get("name", ""), b.get("desc", "")]})
			lines.append({"who": "kurumi", "face": "tilt", "text": "这 %d 天结束时，净资产要达到 %s……" % [int(a.days_boss), GameDate.yen(run.target())]})
	if session.account.credit > 0.0:
		lines.append({"who": "narrator", "text": "海外业者的入金奖金：赠金 %s（可当保证金，不能出金）。" % GameDate.yen(session.account.credit)})
	if run.friends.has("mebuki"):
		lines.append({"who": "mebuki", "face": "happy", "text": "学姐！我每天都会在时间线上告诉你我的预测哦！"})
	screen._on_script_dialog(lines)

# ---------------------------------------------------------------- 仲间

func _add_friend_buttons() -> void:
	for f in run.friends:
		_charges[f] = int(run.friend_def(f).get("active", {}).get("charges", 1))
	screen.add_extra_tab("仲间/道具", _build_tab)
	screen.exit_label = "保存并退出（本节点作废）"
	screen.exit_cb = func():
		run.save()
		Game.goto("res://src/scenes/title.tscn")

func _build_tab(box: VBoxContainer) -> void:
	if run.friends.is_empty() and run.items.is_empty():
		box.add_child(UI.label("没有同行的仲间，也没有道具。", UI.DIM))
	for f in run.friends:
		var fd := run.friend_def(f)
		var act: Dictionary = fd.get("active", {})
		var h := UI.hbox(4)
		var b := UI.button("%s（%d）" % [act.get("name", ""), int(_charges.get(f, 0))], _use_friend.bind(f, null), 96)
		b.disabled = int(_charges.get(f, 0)) <= 0
		h.add_child(b)
		var l := UI.label("%s：%s" % [fd.name, act.get("desc", "")], Color(String(fd.color)))
		l.custom_minimum_size.x = 270
		l.clip_text = true
		l.tooltip_text = "%s
被动：%s" % [fd.bio, fd.passive_desc]
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(l)
		box.add_child(h)
	for i in run.items.size():
		var it := run.item_def(run.items[i])
		if not it.get("use", "map") in ["trade", "both"]:
			continue
		var h2 := UI.hbox(4)
		h2.add_child(UI.button("用：" + it.get("name", ""), _use_item.bind(i), 96))
		var l2 := UI.label(it.get("desc", ""), UI.DIM)
		l2.custom_minimum_size.x = 270
		l2.clip_text = true
		h2.add_child(l2)
		box.add_child(h2)

func _use_item(i: int) -> void:
	if i >= run.items.size():
		return
	var it := run.item_def(run.items[i])
	var eff: Dictionary = it.get("effect", {})
	if eff.has("mental"):
		session.kurumi.change(float(eff.mental))
	if eff.has("cure_tilt"):
		session.kurumi.change(maxf(0.0, float(eff.cure_tilt) - session.kurumi.mental))
	run.items.remove_at(i)
	Sfx.play("ok")
	session.kurumi.say_text("（%s）" % it.get("name", ""), "happy")
	screen.refresh_tab_now()

func _use_friend(f: String, b: Button) -> void:
	if int(_charges.get(f, 0)) <= 0 or screen.finished:
		return
	_charges[f] = int(_charges[f]) - 1
	if b:
		b.disabled = _charges[f] <= 0
	Sfx.play("ok")
	match f:
		"mochiko":
			session.mods.set_layer("cold_eye", {"show_trend": 1, "show_clusters": 1})
			_cold_eye_until = session.market.tick + MarketSim.TICKS_PER_DAY
			session.kurumi.say_text("萌智子：「趋势和止损的位置，都写在图上了。剩下的你自己判断。」", "focus")
		"mebuki":
			var amt := session.account.equity() * 0.5
			session.account.deposit(amt)
			extra.loan = float(extra.loan) + amt
			session.events.post_text("芽吹带你去借了 %s（年利109.5%%）" % GameDate.yen(amt), "news", "coin", 1)
			session.kurumi.say_text("芽吹：「借来的钱也是钱！冲吧学姐！」", "worried")
		"yasuko":
			var sym := screen.selected
			var ins := session.market.get_ins(sym)
			var dir := 1
			for i in range(session.account.history.size() - 1, -1, -1):
				if session.account.history[i].symbol == sym:
					dir = int(session.account.history[i].side)
					break
			for p in session.account.positions:
				if p.symbol == sym:
					dir = p.side
			var mag := session.market.daily_vol(ins) * 0.45 * dir
			session.market.add_effect("pair:" + sym, "level", mag, 1, 6, 30, 0.5, "hype")
			ins.long_ratio = clampf(ins.long_ratio + 0.15 * dir, 0.08, 0.92)
			session.events.post_sns("@あふぃちゃん", "【あふぃちゃん】%s 现在就是%s的好时机！大家跟上♪" % [ins.name, "买" if dir > 0 else "卖"])
	screen._refresh_all()
	screen.refresh_tab_now()

# ---------------------------------------------------------------- 每日/每 tick

func _on_tick() -> void:
	if _cold_eye_until > 0 and session.market.tick >= _cold_eye_until:
		_cold_eye_until = -1
		session.mods.remove_layer("cold_eye")
	if not session.account.positions.is_empty():
		_had_position_today = true

func _on_day(_d: int) -> void:
	if run.curses.has("posipos") and not _had_position_today:
		session.kurumi.change(-6.0)
		session.kurumi.say_text("（一整天都没有持仓……手好痒……）", "tilt")
	_had_position_today = not session.account.positions.is_empty()
	if run.friends.has("yasuko"):
		extra.affi_fp = int(extra.affi_fp) + 4
	if run.friends.has("mebuki"):
		_mebuki_prophecy()

func _mebuki_prophecy() -> void:
	var syms := session.symbols
	var sym: String = syms[session.market.rng.randi() % syms.size()]
	var ins := session.market.get_ins(sym)
	var ub: MarketSim.Unit = session.market.units[ins.base]
	var uq: MarketSim.Unit = session.market.units[ins.quote]
	var rd := (1 if ub.regime == 1 else (-1 if ub.regime == 2 else 0)) - (1 if uq.regime == 1 else (-1 if uq.regime == 2 else 0))
	var truth := signi(rd)
	if truth == 0:
		truth = 1 if session.market.rng.randf() < 0.5 else -1
	var call := -truth if session.market.rng.randf() < 0.75 else truth
	session.events.post_sns("@芽吹", "今天的 %s 绝对%s！我的直觉这么说的！全力%s！" % [ins.name, "涨" if call > 0 else "跌", "买" if call > 0 else "卖"])
	session.kurumi.say("mebuki_call")

# ---------------------------------------------------------------- 结束

func _on_done(result: Dictionary) -> void:
	# 零cut券用掉了就移除
	for ln in session.mods.layer_names():
		if String(ln).begins_with("zero_cut_spent") and run.relics.has("hourglass"):
			run.relics.erase("hourglass")
			break
	var info := run.settle_trade(node, result, extra)
	info.node = node.id
	var failed := ""
	if result.reason == "broken" or run.mental <= 0.0:
		failed = "broken"
	elif run.money < 10000.0 and node.type != "boss":
		failed = "bankrupt"
	info.failed = failed
	run.in_node = ""
	run.save()
	_summary(result, info)

func _summary(result: Dictionary, info: Dictionary) -> void:
	var v := UI.modal(screen._popup_layer, UI.YELLOW if info.get("failed", "") == "" else UI.UP, 360)
	var title := "交易结束"
	if node.type == "boss":
		title = "BOSS 结算：" + ("达成目标！" if info.get("passed", false) else "未达成目标……")
	v.add_child(UI.label(title, UI.YELLOW if info.get("passed", true) else UI.UP))
	var t := "盈亏 [color=#%s]%s[/color]（%+.1f%%）\n" % [UI.hex(UI.up_down(float(info.profit))), GameDate.yen(float(info.profit), true), float(info.ret) * 100.0]
	t += "交易 %d 次 · 胜 %d · 强平 %d\n" % [int(result.stats.trades), int(result.stats.wins), int(result.stats.stopouts)]
	if float(result.debt) > 0.0:
		t += "[color=#%s]不足金 %s 计入借金[/color]\n" % [UI.hex(UI.UP), GameDate.yen(float(result.debt))]
	if float(extra.loan) > 0.0:
		t += "借入 %s 计入借金\n" % GameDate.yen(float(extra.loan))
	t += "获得 FP [color=#ffd166]%d[/color]%s\n" % [int(info.fp), "（含目标奖励）" if info.get("goal_hit", false) and node.type == "trade" else ""]
	t += "资金 %s · 借金 %s · 净资产 %s" % [GameDate.yen(run.money), GameDate.yen(run.debt), GameDate.yen(run.net())]
	if node.type == "boss":
		t += "\n目标 %s" % GameDate.yen(run.target())
	match String(info.get("failed", "")):
		"broken": t += "\n\n[color=#%s]久留美的心，折断了。[/color]" % UI.hex(UI.UP)
		"bankrupt": t += "\n\n[color=#%s]资金几乎归零……[/color]" % UI.hex(UI.UP)
	v.add_child(UI.rich(t))
	v.add_child(UI.button("继续", func():
		Game.goto("res://src/run/run_map.tscn", {"after_trade": info})))
