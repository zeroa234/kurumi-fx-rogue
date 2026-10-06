extends Control
## 肉鸽地图：选择下一个节点；事件/商店/休息在本场景以弹窗处理；交易节点切到 run_trade。

var run: RunState
var map_area: Control
var side: VBoxContainer
var top_lbl: RichTextLabel
var mental_bar: ProgressBar
var hint: Label
var fp_lbl: Label
var node_btns := {}

const MAP_RECT := Rect2(8, 40, 430, 280)

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	run = Game.run
	if run == null:
		Game.goto("res://src/run/run_hub.tscn")
		return
	var fill := ColorRect.new()
	fill.color = UI.BG
	fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(fill)
	var bg := TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.texture = UI.tex("res://assets/sprites/bg/bg_city_night.png")
	bg.modulate = Color(0.35, 0.32, 0.45)
	add_child(bg)
	_build()
	_refresh()
	if Game.params.get("intro", false):
		Game.params.erase("intro")
		_act_intro()
	elif Game.params.has("after_trade"):
		var info: Dictionary = Game.params.after_trade
		Game.params.erase("after_trade")
		_after_trade(info)

func _build() -> void:
	var top := UI.panel(Color("140f22"), UI.BORDER)
	top.position = Vector2(0, 0)
	top.size = Vector2(640, 34)
	add_child(top)
	var th := UI.hbox(6)
	top.add_child(th)
	top_lbl = UI.rich()
	top_lbl.custom_minimum_size = Vector2(440, 28)
	th.add_child(top_lbl)
	th.add_child(AnimSprite.make("res://assets/sprites/anim/coin.png", 24, 10.0))
	fp_lbl = UI.label("", UI.YELLOW)
	fp_lbl.custom_minimum_size.x = 50
	fp_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	th.add_child(fp_lbl)
	var mv := UI.vbox(1)
	mv.add_child(UI.label("メンタル", UI.PINK))
	mental_bar = ProgressBar.new()
	mental_bar.custom_minimum_size = Vector2(100, 8)
	mental_bar.show_percentage = false
	mv.add_child(mental_bar)
	th.add_child(mv)
	map_area = Control.new()
	map_area.position = MAP_RECT.position
	map_area.size = MAP_RECT.size
	add_child(map_area)
	var sp := UI.panel(UI.PANEL, UI.BORDER)
	sp.position = Vector2(446, 38)
	sp.size = Vector2(190, 300)
	add_child(sp)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(184, 294)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sp.add_child(sc)
	side = UI.vbox(3)
	side.custom_minimum_size.x = 176
	sc.add_child(side)
	hint = UI.label("", UI.DIM)
	hint.position = Vector2(8, 340)
	add_child(hint)

func _refresh() -> void:
	var a := run.act_def()
	top_lbl.text = "[color=#%s]%s[/color]  目标 净资产 %s\n资金 %s  借金 [color=#%s]%s[/color]  净资产 %s  %s" % [
		UI.hex(UI.PINK), a.name, GameDate.yen(run.target()),
		GameDate.yen(run.money), UI.hex(UI.UP if run.debt > 0 else UI.DIM), GameDate.yen(run.debt), GameDate.yen(run.net()),
		("挑战度%d" % run.ascension) if run.ascension > 0 else ""]
	fp_lbl.text = "%d FP" % run.fp
	mental_bar.max_value = run.mods.get_v("mental_max")
	mental_bar.value = run.mental
	_draw_map()
	_draw_side()
	hint.text = "选择下一个节点。" if not run.available().is_empty() else ""

func _draw_map() -> void:
	for c in map_area.get_children():
		c.queue_free()
	node_btns.clear()
	var avail := run.available()
	var lines := MapLines.new()
	lines.run = run
	lines.size = MAP_RECT.size
	lines.pos_fn = _node_pos
	map_area.add_child(lines)
	for row in run.map:
		for n in row:
			var b := TextureButton.new()
			b.texture_normal = PixelIcons.get_icon("node_" + n.type, 2)
			b.position = _node_pos(n) - Vector2(8, 8)
			b.size = Vector2(16, 16)
			b.tooltip_text = _node_tip(n)
			var is_av: bool = avail.has(n.id)
			b.disabled = not is_av
			if n.done:
				b.modulate = Color(0.45, 0.45, 0.55)
			elif not is_av:
				b.modulate = Color(0.75, 0.72, 0.85)
			else:
				var tw := b.create_tween().set_loops()
				tw.tween_property(b, "modulate", Color(1.5, 1.4, 0.8), 0.45)
				tw.tween_property(b, "modulate", Color(1, 1, 1), 0.45)
			b.pressed.connect(_choose.bind(n.id))
			map_area.add_child(b)
			node_btns[n.id] = b
	# 久留美的位置
	var cur := run.node(run.current)
	var chibi := TextureRect.new()
	var ct := UI.tex("res://assets/sprites/chibi/kurumi_chibi.png")
	chibi.texture = ct if ct else Portraits.small("kurumi")
	chibi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chibi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chibi.size = Vector2(28, 28)
	chibi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if cur.is_empty():
		chibi.position = Vector2(2, MAP_RECT.size.y / 2.0 - 14)
	else:
		chibi.position = _node_pos(cur) + Vector2(-14, -34)
	map_area.add_child(chibi)

func _node_pos(n: Dictionary) -> Vector2:
	var li: int = int(n.layer)
	var count: int = run.map[li].size()
	var x := 34.0 + li * (MAP_RECT.size.x - 60.0) / (RunState.MAP_LAYERS - 1)
	var y := MAP_RECT.size.y * (float(int(n.idx)) + 1.0) / (count + 1.0)
	return Vector2(roundf(x), roundf(y))

func _node_tip(n: Dictionary) -> String:
	match n.type:
		"trade": return "相場：%d 个交易日。达到 +%d%% 有额外 FP。" % [int(run.act_def().days_trade), int(float(run.act_def().goal_pct) * 100)]
		"elite":
			var e := run.elite_def(n.get("elite", ""))
			return "精英「%s」：%s\n奖励：FP 更多 + 选择 1 个手法" % [e.get("name", ""), e.get("desc", "")]
		"event": return "事件"
		"shop": return "商店"
		"rest": return "休息：打工 / 睡觉 / 复盘"
		"boss":
			var b := run.boss_def(n.get("boss", ""))
			return "BOSS「%s」：%s\n结束时净资产需达到 %s" % [b.get("name", ""), b.get("desc", ""), GameDate.yen(run.target())]
	return ""

func _draw_side() -> void:
	for c in side.get_children():
		c.queue_free()
	var b := run.broker()
	side.add_child(UI.label("业者：%s %d倍" % [b.get("name", ""), int(b.get("leverage", 25))], UI.DIM))
	if not run.friends.is_empty():
		side.add_child(UI.label("仲间", UI.YELLOW))
		for f in run.friends:
			var fd := run.friend_def(f)
			var l := UI.label("· " + fd.get("name", f), Color(String(fd.get("color", "ffffff"))))
			l.tooltip_text = "%s\n主动「%s」：%s" % [fd.passive_desc, fd.active.name, fd.active.desc]
			l.mouse_filter = Control.MOUSE_FILTER_PASS
			side.add_child(l)
	side.add_child(UI.label("手法 (%d)" % run.relics.size(), UI.YELLOW))
	var grid := GridContainer.new()
	grid.columns = 5
	for rid in run.relics:
		var r := run.relic_def(rid)
		var t := TextureRect.new()
		t.texture = UI.icon(r.get("icon", ""), "star")
		t.custom_minimum_size = Vector2(32, 32)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		t.tooltip_text = "%s\n%s" % [r.get("name", rid), r.get("desc", "")]
		grid.add_child(t)
	side.add_child(grid)
	side.add_child(UI.label("道具 (%d/%d)" % [run.items.size(), run.item_slots()], UI.YELLOW))
	for i in run.items.size():
		var it := run.item_def(run.items[i])
		var h := UI.hbox(3)
		var ic := TextureRect.new()
		ic.texture = UI.icon(it.get("icon", ""), "coin")
		ic.custom_minimum_size = Vector2(16, 16)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var nl := UI.label(it.get("name", ""), UI.TEXT)
		nl.custom_minimum_size.x = 100
		nl.tooltip_text = it.get("desc", "")
		nl.mouse_filter = Control.MOUSE_FILTER_PASS
		h.add_child(nl)
		if it.get("use", "map") in ["map", "both"]:
			h.add_child(UI.button("用", _use_item.bind(i)))
		side.add_child(h)
	if not run.curses.is_empty():
		side.add_child(UI.label("诅咒", UI.UP))
		for c in run.curses:
			var cd := run.curse_def(c)
			var cl := UI.label("· " + cd.get("name", c), UI.UP)
			cl.tooltip_text = cd.get("desc", "")
			cl.mouse_filter = Control.MOUSE_FILTER_PASS
			side.add_child(cl)
	if run.debt > 0.0:
		side.add_child(UI.button("还款（%s）" % GameDate.yen(minf(run.debt, run.money)), func():
			var p := run.repay(run.debt)
			_toast("还款 %s" % GameDate.yen(p))
			run.save()
			_refresh()))
	side.add_child(UI.label("─────", UI.MUTED))
	side.add_child(UI.button("保存并返回标题", func():
		run.save()
		Game.goto("res://src/scenes/title.tscn")))
	side.add_child(UI.button("放弃本局", func():
		var v := UI.modal(self, UI.UP, 260)
		v.add_child(UI.label("确定放弃这一局吗？", UI.UP))
		var h := UI.hbox(8)
		h.add_child(UI.button("放弃", func():
			run.ended = true
			run.end_reason = "abandon"
			Game.goto("res://src/run/run_result.tscn")))
		h.add_child(UI.button("取消", func(): UI.close_modal(v)))
		v.add_child(h)))

func _toast(t: String, col: Color = UI.YELLOW) -> void:
	var l := UI.label(t, col)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UI.box(Color(0.05, 0.03, 0.1, 0.92), col, 1, 3))
	p.add_child(l)
	add_child(p)
	p.position = Vector2(100, 300)
	var tw := create_tween()
	tw.tween_interval(2.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.4)
	tw.tween_callback(p.queue_free)

func _use_item(i: int) -> void:
	var t := run.use_item(i)
	Sfx.play("ok")
	_toast(t)
	run.save()
	_refresh()

# ================================================================ 节点

func _choose(id: String) -> void:
	var n := run.enter(id)
	run.save()
	match String(n.type):
		"trade", "elite", "boss":
			if n.type == "trade" and run.skip_next:
				run.skip_next = false
				run.fp += int(15 * run.mods.get_v("fp_mult"))
				run.complete_current()
				run.save()
				_toast("有给休假：跳过了这个交易节点（FP +15）")
				_refresh()
				return
			run.in_node = id
			run.save()
			Game.goto("res://src/run/run_trade.tscn", {"node": id})
		"event": _open_event(n)
		"shop": _open_shop()
		"rest": _open_rest()

func _finish_node() -> void:
	run.complete_current()
	var f := run.check_fail()
	if f != "":
		run.ended = true
		run.end_reason = f
		run.save()
		Game.goto("res://src/run/run_result.tscn")
		return
	run.save()
	_refresh()

# ---------------------------------------------------------------- 事件

func _open_event(n: Dictionary) -> void:
	var ev: Dictionary = DB.find("res://data/run/events.json", "events", n.get("event", ""))
	if ev.is_empty():
		run.fp += 10
		_finish_node()
		return
	Save.codex_add("events", ev.id)
	var v := UI.modal(self, UI.YELLOW, 420)
	var h := UI.hbox(6)
	var por := TextureRect.new()
	por.texture = Portraits.small(ev.get("who", "kurumi"), ev.get("face", "normal")) if ev.get("who", "narrator") != "narrator" else null
	por.custom_minimum_size = Vector2(64, 64)
	h.add_child(por)
	var tv := UI.vbox(3)
	tv.add_child(UI.label(ev.title, UI.YELLOW))
	var tx := UI.rich(ev.text)
	tx.custom_minimum_size.x = 340
	tv.add_child(tx)
	h.add_child(tv)
	v.add_child(h)
	for ch in ev.choices:
		var ok := _req_ok(ch.get("req", {}))
		var b := UI.button(ch.text, func():
			var res := run.apply_effects(ch.get("effects", {}))
			UI.close_modal(v)
			_result_popup(ev.title, res if res != "" else "什么也没发生。"))
		b.disabled = not ok
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)

func _req_ok(req: Dictionary) -> bool:
	if req.has("fp") and run.fp < int(req.fp):
		return false
	if req.has("money_pct_min") and run.money < 10000.0:
		return false
	return true

func _result_popup(title: String, text: String) -> void:
	var v := UI.modal(self, UI.YELLOW, 320)
	v.add_child(UI.label(title, UI.YELLOW))
	var r := UI.rich(text)
	v.add_child(r)
	v.add_child(UI.button("继续", func():
		UI.close_modal(v)
		_finish_node()))

# ---------------------------------------------------------------- 商店

func _open_shop() -> void:
	if not run.shop_cache.has(run.current):
		run.shop_cache[run.current] = run.gen_shop()
		run.shop_cache[run.current].free_rerolls = Save.meta_level("reroll1")
	_shop_ui()

func _shop_ui() -> void:
	var shop: Dictionary = run.shop_cache[run.current]
	var v := UI.modal(self, UI.CYAN, 440)
	var head := UI.hbox(8)
	head.add_child(UI.label("便利店 & 书店", UI.CYAN))
	head.add_child(AnimSprite.make("res://assets/sprites/anim/coin.png", 24, 10.0))
	head.add_child(UI.label("%d FP" % run.fp, UI.YELLOW))
	v.add_child(head)
	v.add_child(UI.label("手法", UI.DIM))
	for s in shop.relics:
		var r := run.relic_def(s.id)
		var h := UI.hbox(4)
		var ic := TextureRect.new()
		ic.texture = UI.icon(r.get("icon", ""), "star")
		ic.custom_minimum_size = Vector2(24, 24)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var l := UI.label("%s〔%s〕%s" % [r.name, {"common": "普通", "uncommon": "优秀", "rare": "稀有"}.get(r.rarity, ""), r.desc], UI.TEXT if not s.sold else UI.MUTED)
		l.custom_minimum_size.x = 330
		l.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		h.add_child(l)
		var b := UI.button("已售" if s.sold else "%d FP" % s.price, func():
			if run.fp >= int(s.price) and not s.sold:
				run.fp -= int(s.price)
				s.sold = true
				run.add_relic(s.id)
				Sfx.play("buy")
				UI.close_modal(v)
				_shop_ui())
		b.disabled = s.sold or run.fp < int(s.price)
		h.add_child(b)
		v.add_child(h)
	v.add_child(UI.label("道具", UI.DIM))
	var ih := UI.hbox(4)
	for s in shop.items:
		var it := run.item_def(s.id)
		var b2 := UI.button("已售" if s.sold else "%s %dFP" % [it.name, s.price], func():
			if run.fp >= int(s.price) and not s.sold and run.add_item(s.id):
				run.fp -= int(s.price)
				s.sold = true
				Sfx.play("buy")
				UI.close_modal(v)
				_shop_ui())
		b2.tooltip_text = it.desc
		b2.disabled = s.sold or run.fp < int(s.price) or run.items.size() >= run.item_slots()
		ih.add_child(b2)
	v.add_child(ih)
	var sh := UI.hbox(4)
	var heal_p := run.price(30)
	var hb := UI.button("休息一下 メンタル+30（%dFP）" % heal_p, func():
		if run.fp >= heal_p:
			run.fp -= heal_p
			run.mental = minf(run.mods.get_v("mental_max"), run.mental + 30.0)
			UI.close_modal(v)
			_shop_ui())
	hb.disabled = run.fp < heal_p
	sh.add_child(hb)
	var cure_p := run.price(50)
	var cb := UI.button("驱除诅咒（%dFP）" % cure_p, func():
		if run.fp >= cure_p and not run.curses.is_empty():
			run.fp -= cure_p
			run.remove_curse()
			UI.close_modal(v)
			_shop_ui())
	cb.disabled = run.fp < cure_p or run.curses.is_empty()
	sh.add_child(cb)
	var free := int(shop.get("free_rerolls", 0))
	var rr_p := 0 if free > 0 else run.price(15)
	var rb := UI.button("刷新手法（%s）" % ("免费" if rr_p == 0 else "%dFP" % rr_p), func():
		if run.fp >= rr_p:
			run.fp -= rr_p
			if free > 0:
				shop.free_rerolls = free - 1
			shop.relics.clear()
			for r in run.roll_relics(3):
				shop.relics.append({"id": r.id, "price": run.relic_price(r), "sold": false})
			UI.close_modal(v)
			_shop_ui())
	rb.disabled = run.fp < rr_p
	sh.add_child(rb)
	v.add_child(sh)
	v.add_child(UI.button("离开商店", func():
		UI.close_modal(v)
		_finish_node()))
	_refresh()

# ---------------------------------------------------------------- 休息

func _open_rest() -> void:
	var v := UI.modal(self, UI.DOWN, 360)
	v.add_child(UI.label("休息", UI.DOWN))
	var pay := run.act_money_base() * run.mods.get_v("work_pay_mult")
	v.add_child(UI.button("便利店打工：资金 +%s（メンタル -5）" % GameDate.yen(pay), func():
		run.money += pay
		run.mental = maxf(1.0, run.mental - 5.0)
		UI.close_modal(v)
		_result_popup("打工", "工资 %s 到手。" % GameDate.yen(pay))))
	v.add_child(UI.button("好好睡一觉：メンタル +35", func():
		run.mental = minf(run.mods.get_v("mental_max"), run.mental + 35.0)
		UI.close_modal(v)
		_result_popup("睡觉", "メンタル +35")))
	v.add_child(UI.button("复盘笔记：FP +30", func():
		run.fp += int(30 * run.mods.get_v("fp_mult"))
		UI.close_modal(v)
		_result_popup("复盘", "FP +%d" % int(30 * run.mods.get_v("fp_mult")))))

# ================================================================ 交易之后

func _after_trade(info: Dictionary) -> void:
	var n := run.node(info.get("node", ""))
	if info.get("failed", "") != "":
		run.ended = true
		run.end_reason = info.failed
		run.save()
		Game.goto("res://src/run/run_result.tscn")
		return
	if n.type == "boss":
		if info.get("passed", false):
			_boss_clear(n)
		else:
			run.ended = true
			run.end_reason = "target"
			run.save()
			Game.goto("res://src/run/run_result.tscn")
		return
	if n.type == "elite":
		_relic_choice(run.roll_relics(3, "uncommon"), "精英奖励：选择 1 个手法", func(): _finish_node())
		return
	_finish_node()

func _relic_choice(choices: Array, title: String, done: Callable) -> void:
	if choices.is_empty():
		run.fp += 30
		done.call()
		return
	var v := UI.modal(self, UI.YELLOW, 440)
	v.add_child(UI.label(title, UI.YELLOW))
	for r in choices:
		var h := UI.hbox(6)
		var ic := TextureRect.new()
		ic.texture = UI.icon(r.get("icon", ""), "star")
		ic.custom_minimum_size = Vector2(32, 32)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var b := UI.button("%s〔%s〕\n%s" % [r.name, {"common": "普通", "uncommon": "优秀", "rare": "稀有"}.get(r.rarity, ""), r.desc], func():
			run.add_relic(r.id)
			UI.close_modal(v)
			done.call())
		b.custom_minimum_size.x = 380
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		h.add_child(b)
		v.add_child(h)
	v.add_child(UI.button("跳过（FP +20）", func():
		run.fp += 20
		UI.close_modal(v)
		done.call()))

func _boss_clear(n: Dictionary) -> void:
	run.bosses_beaten.append(n.get("boss", ""))
	Save.codex_add("bosses", n.get("boss", ""))
	run.mental = minf(run.mods.get_v("mental_max"), run.mental + 30.0)
	var final_act := run.act >= 3 and not run.used_specials.has("endless")
	_relic_choice(run.roll_relics(3, "rare"), "击败 BOSS！选择 1 个手法", func():
		run.complete_current()
		if final_act:
			_victory()
			return
		run.next_act()
		run.save()
		_refresh()
		_act_intro())

func _victory() -> void:
	run.victory = true
	run.save()
	var v := UI.modal(self, UI.PINK, 420)
	v.add_child(UI.label("2000万円，达成！", UI.PINK, 24))
	var t := UI.rich("净资产 [color=#ffd166]%s[/color]。\n妈妈输掉的2000万円——久留美，取回来了。\n\n[color=#a89cc8]……屏幕上的报价还在跳动。通关后的特殊事件（暴涨？暴跌？还是从未见过的走势？）尚未开放，敬请期待。[/color]" % GameDate.yen(run.net()))
	v.add_child(t)
	var h := UI.hbox(8)
	h.add_child(UI.button("结算", func():
		run.ended = true
		run.end_reason = "victory"
		Game.goto("res://src/run/run_result.tscn")))
	h.add_child(UI.button("继续：无尽模式（目标 1億円）", func():
		run.used_specials["endless"] = true
		run.victory = false
		Save.data.stats.clears = int(Save.data.stats.clears) + 1
		Save.data.meta.max_ascension = maxi(int(Save.data.meta.max_ascension), mini(10, run.ascension + 1))
		run.next_act()
		run.save()
		UI.close_modal(v)
		_refresh()
		_act_intro()))
	v.add_child(h)

func _act_intro() -> void:
	var a := run.act_def()
	var v := UI.modal(self, UI.PINK, 360)
	v.add_child(UI.label(a.name, UI.PINK, 24))
	v.add_child(UI.label("本幕目标：Boss 结束时净资产 ≥ %s" % GameDate.yen(run.target()), UI.YELLOW))
	v.add_child(UI.label("当前净资产 %s" % GameDate.yen(run.net()), UI.TEXT))
	v.add_child(UI.button("出发", func(): UI.close_modal(v)))
