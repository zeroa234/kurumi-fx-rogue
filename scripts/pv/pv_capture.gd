extends Node
## PV 实机素材录制驱动（配合 Godot Movie Maker）。由 scripts/pv/capture_all.sh 调用：
##   godot --path . --write-movie <dir>/f.png --fixed-fps 30 --quit-after <帧数> res://scripts/pv/pv_capture.tscn -- --clip=<名字>
## 每个片段用真实的游戏场景与真实的模拟行情，驱动只代替玩家按按钮：关弹窗、调速度、下单/平仓、翻对话。
## 录出来的是 640×360 原生画面，合成时最近邻放大到 1920×1080。片段的取用区间写在 config/pv-edit.json。

var clip := ""
var ts: TradeScreen

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--clip="):
			clip = a.substr(7)
	# 录制时不弹「指标即将发布」自动暂停（只改内存里的设置，不写盘）
	Save.data.settings["auto_pause_indicator"] = false
	# 驱动本身是启动场景；换场景会释放 current_scene，所以先放一个占位节点顶替它
	await get_tree().process_frame
	var dummy := Node.new()
	get_tree().root.add_child(dummy)
	get_tree().current_scene = dummy
	match clip:
		"title": Game.goto("res://src/scenes/title.tscn")
		"lehman": _story("ch01", 2, _lehman)
		"snb": _story("ch11", 2, _snb)
		"trade": _trade()
		"dialogue": _story("ch08", 1, _dialogue)
		"map":
			Game.run = RunState.create({"broker": "overseas", "friends": ["mochiko", "mebuki"], "seed": 777})
			Game.goto("res://src/run/run_map.tscn")
		"hub": Game.goto("res://src/run/run_hub.tscn")
		"meta": Game.goto("res://src/run/meta_screen.tscn")
		"codex": Game.goto("res://src/scenes/codex.tscn")
		"chapters":
			# 同标题画面 Shift+F9，但只改内存、不写盘：章节全部显示为已解锁
			Save.data.story.tutorial_done = true
			for c in StoryDB.all():
				if not Save.data.story.cleared.has(c.id):
					Save.data.story.cleared.append(c.id)
			Game.goto("res://src/scenes/chapter_select.tscn")
		_: push_error("未知片段 " + clip)

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

## 打开剧情某场景，等它建好后交给 then(player)
func _story(ch: String, idx: int, then: Callable) -> void:
	Game.goto("res://src/story/story_player.tscn", {"chapter": ch, "scene_index": idx})
	var sp: Node = null
	while sp == null or not sp.has_method("_play_trade"):
		await get_tree().process_frame
		sp = get_tree().current_scene
	await _frames(3)
	await then.call(sp)

func _buttons(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is Button:
			out.append(c)
		out.append_array(_buttons(c))
	return out

## 关掉交易画面上的对话框与「明白了」提示
func _close_modals() -> void:
	if ts == null or not is_instance_valid(ts):
		return
	for p in ts._popup_layer.get_children():
		if p is DialogueBox:
			p._end()
	for b in _buttons(ts._popup_layer):
		if b.text in ["明白了", "继续"] and b.is_visible_in_tree():
			b.pressed.emit()

## 开局：关掉开场对话，随后交给 TutorialDirector 正常运行
func _enter_trade(sp: Node) -> void:
	ts = sp.trade_screen
	await _frames(2)
	_close_modals()
	await _frames(2)

## 第1章：母亲的澳元/日元（2008年10月回放示意），1 小时图，最快速度
func _lehman(sp: Node) -> void:
	await _enter_trade(sp)
	ts._set_tf(1)
	ts._set_speed(4, true)
	while is_instance_valid(ts) and not ts.finished:
		_close_modals()
		await _frames(1)

## 第11章：快进到 2015-01-15 16:00（第 3 个交易日），然后慢速播放 18:30 下限撤销
func _snb(sp: Node) -> void:
	await _enter_trade(sp)
	var s := ts.session
	var target := s.tick_at(3, 16, 0)
	while s.market.tick < target and not s.done:
		s.advance()
	ts._select_symbol("EURCHF")
	ts._set_tf(0)
	ts._refresh_all()
	ts.chart.queue_redraw()
	ts._set_speed(1, true)
	var shown := 0.0
	while is_instance_valid(ts) and not ts.finished:
		# 弹窗停留 1.5 秒（让画面看得清），再替玩家点掉
		if ts._modal_open:
			shown += get_process_delta_time()
			if shown > 1.5:
				shown = 0.0
				_close_modals()
				ts._set_speed(2, true)
		await _frames(1)

## 交易演示：沙盒同款配置（全部情报能力打开），替玩家下单、设止损止盈、切品种。
## 行情是固定种子的确定性模拟：下单前先用同配置的「影子会话」看后面 N 个 tick 的走向来选方向，
## 好让 PV 里拍到止盈成交（画面上的一切仍是游戏真实逻辑）。
const TRADE_CFG := {
	"seed": 12345, "start_date": "2014-02-03", "days": 5, "balance": 300000.0,
	"broker": {"name": "海外FX", "leverage": 888.0, "stopout": 20.0, "margin_call": 50.0, "zero_cut": true, "spread_mult": 1.5},
	"symbols": ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY", "EURUSD", "EURCHF", "TRYJPY", "N225", "XAUUSD"],
	"act": 2, "goal": {"equity": 1000000.0}, "affi": true,
}

func _trade_mods() -> Mods:
	var mods := Mods.new()
	mods.set_layer("debug", {"ind_ma": 1, "ind_bb": 1, "ind_rsi": 1, "show_fair": 1, "show_clusters": 1, "show_sentiment": 1, "trailing": 1, "forecast_acc": 0.5})
	return mods

## 影子会话：从当前 tick 往后看 ahead 个 tick，返回 {side, fav}（fav = 顺方向最大浮盈 pips，且只算逆向回撤 < 25 pips 之前的部分）
func _peek(sym: String, now_tick: int, ahead: int) -> Dictionary:
	var tw := TradeSession.new(TRADE_CFG.duplicate(true), _trade_mods())
	while tw.market.tick < now_tick:
		tw.advance()
	var ins := tw.market.get_ins(sym)
	var p0 := tw.market.price_of(ins)
	var best := {"side": 1, "fav": 0.0}
	var path: Array[float] = []
	for i in ahead:
		tw.advance()
		path.append(tw.market.price_of(ins))
	for side in [1, -1]:
		var fav := 0.0
		for p in path:
			var mv: float = (p - p0) * side / ins.pip
			if mv < -25.0:
				break
			fav = maxf(fav, mv)
		if fav > best.fav:
			best = {"side": side, "fav": fav}
	tw.dispose()
	return best

func _open_peeked(s: TradeSession, sym: String, ahead: int, lots: float) -> void:
	var pk := _peek(sym, s.market.tick, ahead)
	ts.lots = lots
	ts.sl_pips = 30.0
	ts.tp_pips = maxf(10.0, floorf(pk.fav * 0.8))
	ts._refresh_order()
	ts._place(int(pk.side))
	await _wait(0.5)
	for p in s.account.positions:
		ts._apply_sltp(p)

func _trade() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	get_tree().root.add_child.call_deferred(holder)
	await _frames(1)
	var s := TradeSession.new(TRADE_CFG.duplicate(true), _trade_mods())
	ts = TradeScreen.new(s)
	holder.add_child(ts)
	for i in 60:
		s.advance()
	ts._set_tf(0)
	ts._set_speed(2, true)
	await _wait(1.2)
	await _open_peeked(s, "USDJPY", 70, 10.0)
	ts._set_speed(3, true)
	var t := 0.0
	while not s.account.positions.is_empty() and t < 7.0:
		await _frames(1)
		t += get_process_delta_time()
	await _wait(1.5)
	ts._tabbar.current_tab = 1
	await _wait(1.6)
	ts._tabbar.current_tab = 0
	ts._select_symbol("GBPJPY")
	ts._set_tf(1)
	ts._set_speed(2, true)
	await _wait(0.8)
	await _open_peeked(s, "GBPJPY", 60, 10.0)
	ts._set_speed(3, true)
	while is_instance_valid(ts) and not ts.finished:
		await _frames(1)

## 第8章：四人比赛的对话，每 2.4 秒翻一句
func _dialogue(sp: Node) -> void:
	await _frames(2)
	while true:
		await _wait(2.4)
		var d: DialogueBox = null
		for c in sp.layer.get_children():
			if c is DialogueBox:
				d = c
		if d == null:
			break
		d._advance()
		if d._shown < d._full.length():
			d._advance()
