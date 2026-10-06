class_name Account
extends RefCounted
## 交易账户：持仓、证拠金、止损止盈、强平、零 cut / 追证、掉期。
## 金额单位一律日元。

signal opened(pos: Position)
signal closed(pos: Position, pnl: float, reason: String)
signal margin_warning(level: float)
signal stopped_out(equity_after: float)
signal swap_settled(total: float)
signal zero_cut_used(amount: float)

class Position:
	var id: int
	var symbol: String
	var side: int # +1 买 / -1 卖
	var lots: float
	var entry: float
	var sl := 0.0
	var tp := 0.0
	var trail := 0.0
	var open_tick: int
	var after_event := false
	var peak := 0.0 # 用于追踪止损

	func dir_name() -> String:
		return "买" if side > 0 else "卖"

var market: MarketSim
var mods: Mods
var broker := {
	"id": "domestic",
	"name": "国内大手FX",
	"leverage": 25.0,
	"stopout": 100.0,
	"margin_call": 150.0,
	"zero_cut": false,
	"spread_mult": 1.0,
	"swap_mult": 1.0,
	"swap_fee": 0.003,
	"slip_mult": 1.0,
}
var balance := 0.0
var credit := 0.0 # 海外业者赠金：可作证拠金，不可出金，强平时先扣
var debt := 0.0
var positions: Array[Position] = []
var history: Array[Dictionary] = []
var next_id := 1
var rng: RandomNumberGenerator
var last_event_tick := -999
var insurance_used_day := -1
var warned := false
var stats := {
	"trades": 0, "wins": 0, "losses": 0,
	"gross_win": 0.0, "gross_loss": 0.0,
	"max_equity": 0.0, "max_drawdown": 0.0,
	"stopouts": 0, "swap": 0.0,
}

func _init(m: MarketSim, md: Mods, start_balance: float, broker_def := {}) -> void:
	market = m
	mods = md
	balance = start_balance
	rng = RandomNumberGenerator.new()
	rng.seed = m.rng.seed ^ 0x5eed
	for k in broker_def:
		broker[k] = broker_def[k]
	stats.max_equity = start_balance

# ---------------------------------------------------------------- 估值

func leverage() -> float:
	return float(broker.leverage) * mods.get_v("leverage_mult")

func spread_of(ins: MarketSim.Instrument) -> float:
	return ins.spread_now * float(broker.spread_mult) * mods.get_v("spread_mult")

func bid(ins: MarketSim.Instrument) -> float:
	return ins.mid - spread_of(ins) * 0.5

func ask(ins: MarketSim.Instrument) -> float:
	return ins.mid + spread_of(ins) * 0.5

func exit_price(pos: Position) -> float:
	var ins := market.get_ins(pos.symbol)
	return bid(ins) if pos.side > 0 else ask(ins)

func pnl_at(pos: Position, price: float) -> float:
	var ins := market.get_ins(pos.symbol)
	return (price - pos.entry) * pos.side * pos.lots * ins.contract * market.jpy_value(ins.quote)

func floating(pos: Position) -> float:
	return pnl_at(pos, exit_price(pos))

func floating_total() -> float:
	var s := 0.0
	for p in positions:
		s += floating(p)
	return s

func equity() -> float:
	return balance + credit + floating_total()

func notional_jpy(symbol: String, lots: float) -> float:
	var ins := market.get_ins(symbol)
	return lots * ins.contract * market.jpy_value(ins.base)

func margin_for(symbol: String, lots: float) -> float:
	return notional_jpy(symbol, lots) / leverage()

func used_margin() -> float:
	var s := 0.0
	for p in positions:
		s += margin_for(p.symbol, p.lots)
	return s

func free_margin() -> float:
	return equity() - used_margin()

func margin_level() -> float:
	var um := used_margin()
	if um <= 0.0:
		return INF
	return equity() / um * 100.0

func stopout_level() -> float:
	return maxf(5.0, float(broker.stopout) - mods.get_v("stopout_delta"))

## 以当前自由保证金最多能开多少手（0.1 手为单位）
func max_lots(symbol: String) -> float:
	var per := margin_for(symbol, 1.0)
	if per <= 0.0:
		return 0.0
	var n := free_margin() / per * 0.98
	return maxf(0.0, floorf(n * 10.0) / 10.0)

func lot_cap() -> float:
	return 500.0 * mods.get_v("max_lot_mult")

# ---------------------------------------------------------------- 下单

## 返回 Position 或错误字符串
func open_position(symbol: String, side: int, lots: float, sl := 0.0, tp := 0.0) -> Variant:
	var ins := market.get_ins(symbol)
	if ins == null:
		return "没有这个品种"
	if ins.halted:
		return "报价停止中，无法下单！"
	lots = snappedf(lots, 0.1)
	if lots < 0.1:
		return "手数太少"
	if lots > lot_cap():
		return "超过单笔上限 %s 手" % lot_cap()
	if positions.size() >= int(mods.get_v("max_positions")):
		return "持仓数已满（%d）" % int(mods.get_v("max_positions"))
	if margin_for(symbol, lots) > free_margin():
		return "证拠金不足"
	var price := ask(ins) if side > 0 else bid(ins)
	price += side * _market_slip(ins)
	# 同方向逆势加仓（ナンピン）优惠
	var nan := mods.get_v("nanpin")
	if nan > 0.0:
		for p in positions:
			if p.symbol == symbol and p.side == side and floating(p) < 0.0:
				price -= side * absf(price - p.entry) * nan
				break
	var pos := Position.new()
	pos.id = next_id
	next_id += 1
	pos.symbol = symbol
	pos.side = side
	pos.lots = lots
	pos.entry = price
	pos.sl = sl
	pos.tp = tp
	pos.open_tick = market.tick
	pos.after_event = market.tick - last_event_tick <= 8
	pos.peak = price
	positions.append(pos)
	opened.emit(pos)
	return pos

func _market_slip(ins: MarketSim.Instrument) -> float:
	# 正常行情几乎无滑点；波动越大越滑
	var u := clampf(ins.ev_spread - 1.0, 0.0, 30.0)
	return rng.randf() * ins.pip * (0.2 + u * 0.5) * float(broker.slip_mult)

func close_position(pos: Position, reason := "手动", price := NAN) -> float:
	if not positions.has(pos):
		return 0.0
	var ins := market.get_ins(pos.symbol)
	if ins.halted and reason == "手动":
		return 0.0 # 报价停止中，无法手动平仓
	if is_nan(price):
		price = exit_price(pos)
		if reason == "手动":
			price -= pos.side * _market_slip(ins)
	var pnl := pnl_at(pos, price)
	pnl = _apply_pnl_mods(pos, pnl)
	balance += pnl
	positions.erase(pos)
	stats.trades += 1
	if pnl >= 0.0:
		stats.wins += 1
		stats.gross_win += pnl
	else:
		stats.losses += 1
		stats.gross_loss += -pnl
		var ins_rate := mods.get_v("insurance")
		var today := market.day_index()
		if ins_rate > 0.0 and insurance_used_day != today:
			insurance_used_day = today
			balance += -pnl * ins_rate
	history.append({
		"symbol": pos.symbol, "side": pos.side, "lots": pos.lots,
		"entry": pos.entry, "exit": price, "pnl": pnl, "reason": reason,
		"open_tick": pos.open_tick, "close_tick": market.tick,
	})
	closed.emit(pos, pnl, reason)
	return pnl

func _apply_pnl_mods(pos: Position, pnl: float) -> float:
	if pnl > 0.0:
		var m := mods.get_v("profit_mult")
		var tb := mods.get_v("trend_profit")
		if tb > 0.0:
			var ins := market.get_ins(pos.symbol)
			var ub: MarketSim.Unit = market.units[ins.base]
			var uq: MarketSim.Unit = market.units[ins.quote]
			var trend_dir := (1 if ub.regime == 1 else (-1 if ub.regime == 2 else 0)) - (1 if uq.regime == 1 else (-1 if uq.regime == 2 else 0))
			if signi(trend_dir) == pos.side:
				m += tb
		if pos.after_event:
			m += mods.get_v("event_profit")
		return pnl * m
	return pnl * mods.get_v("loss_mult")

func close_all(reason := "全部平仓") -> float:
	var total := 0.0
	for p in positions.duplicate():
		total += close_position(p, reason)
	return total

func modify(pos: Position, sl: float, tp: float) -> void:
	pos.sl = sl
	pos.tp = tp

# ---------------------------------------------------------------- 每 tick

## market.step() 之后调用：检查止损/止盈/追踪/强平
func process_tick() -> void:
	for pos in positions.duplicate():
		_check_orders(pos)
	_check_margin()
	var eq := equity()
	if eq > stats.max_equity:
		stats.max_equity = eq
	if stats.max_equity > 0.0:
		stats.max_drawdown = maxf(stats.max_drawdown, 1.0 - eq / stats.max_equity)

func _check_orders(pos: Position) -> void:
	var ins := market.get_ins(pos.symbol)
	var n := ins.c.size()
	if n == 0 or ins.halted:
		return # 报价停止：止损/止盈都无法成交
	var half := spread_of(ins) * 0.5
	var o := ins.o[n - 1]
	var hi := ins.h[n - 1]
	var lo := ins.l[n - 1]
	# 平仓侧价格：多单看 bid，空单看 ask
	var o_x := o - half * pos.side
	var hi_x := hi - half * pos.side
	var lo_x := lo - half * pos.side
	# 追踪止损
	if pos.trail > 0.0 and mods.flag("trailing"):
		if pos.side > 0:
			pos.peak = maxf(pos.peak, hi_x)
			pos.sl = maxf(pos.sl, pos.peak - pos.trail)
		else:
			pos.peak = minf(pos.peak, lo_x) if pos.peak > 0.0 else lo_x
			var cand := pos.peak + pos.trail
			pos.sl = cand if pos.sl <= 0.0 else minf(pos.sl, cand)
	var slip_unit := spread_of(ins) * 0.6 * float(broker.slip_mult) * mods.get_v("sl_slip_mult")
	if pos.side > 0:
		if pos.sl > 0.0 and lo_x <= pos.sl:
			var fill := o_x if o_x < pos.sl else pos.sl - rng.randf() * slip_unit
			close_position(pos, "止损", fill)
			return
		if pos.tp > 0.0 and hi_x >= pos.tp:
			close_position(pos, "止盈", o_x if o_x > pos.tp else pos.tp)
			return
	else:
		if pos.sl > 0.0 and hi_x >= pos.sl:
			var fill2 := o_x if o_x > pos.sl else pos.sl + rng.randf() * slip_unit
			close_position(pos, "止损", fill2)
			return
		if pos.tp > 0.0 and lo_x <= pos.tp:
			close_position(pos, "止盈", o_x if o_x < pos.tp else pos.tp)
			return

func _check_margin() -> void:
	if positions.is_empty():
		warned = false
		return
	var ml := margin_level()
	if ml <= stopout_level():
		_stop_out()
		return
	if ml <= float(broker.margin_call):
		if not warned:
			warned = true
			margin_warning.emit(ml)
	else:
		warned = false

func _stop_out() -> void:
	# 报价停止的品种无法强平（等报价恢复时以恢复后的价格成交）
	var closable := positions.filter(func(p: Position) -> bool: return not market.get_ins(p.symbol).halted)
	if closable.is_empty():
		return
	stats.stopouts += 1
	# 从亏得最多的开始平，直到维持率恢复
	var sorted := closable
	sorted.sort_custom(func(a: Position, b: Position) -> bool: return floating(a) < floating(b))
	for p in sorted:
		var ins := market.get_ins(p.symbol)
		# 强平时流动性差：额外滑点
		var extra := spread_of(ins) * (1.0 + rng.randf() * 2.0) * float(broker.slip_mult)
		close_position(p, "强制平仓", exit_price(p) - p.side * extra)
		if positions.is_empty() or margin_level() > stopout_level() * 1.5:
			break
	settle_negative()
	stopped_out.emit(equity())

## 净值为负时：零 cut 清零，否则变成借金（追证）
func settle_negative() -> void:
	if not positions.is_empty():
		return
	if credit > 0.0 and balance < 0.0:
		var use := minf(credit, -balance)
		credit -= use
		balance += use
	if balance >= 0.0:
		return
	var zc := bool(broker.zero_cut)
	if not zc and mods.get_v("zero_cut") > 0.0:
		zc = true
		mods.set_layer("zero_cut_spent_%d" % market.tick, {"zero_cut": -1.0})
	if zc:
		zero_cut_used.emit(-balance)
		balance = 0.0
		credit = 0.0
	else:
		debt += -balance
		balance = 0.0

## 每日换日时结算掉期；mult = 天数（周三 3 倍）
func settle_swap(mult := 1) -> float:
	var total := 0.0
	for p in positions:
		var ins := market.get_ins(p.symbol)
		var ub: MarketSim.Unit = market.units[ins.base]
		var uq: MarketSim.Unit = market.units[ins.quote]
		var notional := notional_jpy(p.symbol, p.lots)
		var diff := (ub.rate - uq.rate) / 100.0 * p.side
		var daily := notional * (diff * float(broker.swap_mult) * mods.get_v("swap_mult") - float(broker.swap_fee)) / 365.0
		total += daily * mult
	if total != 0.0:
		balance += total
		stats.swap += total
		swap_settled.emit(total)
	return total

## 入金 / 出金（剧情、闇金、打工）
func deposit(amount: float) -> void:
	if debt > 0.0 and amount > 0.0:
		var pay := minf(debt, amount)
		debt -= pay
		amount -= pay
	balance += amount

func withdraw(amount: float) -> float:
	var can := maxf(0.0, minf(minf(amount, free_margin()), balance))
	balance -= can
	return can
