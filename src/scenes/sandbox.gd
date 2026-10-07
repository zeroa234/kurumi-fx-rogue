extends Control
## 调试沙盒：直接进入一段交易，所有情报能力全开。

func _ready() -> void:
	Bgm.play("trade_main")
	var mods := Mods.new()
	mods.set_layer("debug", {"ind_ma": 1, "ind_bb": 1, "ind_rsi": 1, "show_fair": 1, "show_clusters": 1, "show_sentiment": 1, "trailing": 1, "forecast_acc": 0.5})
	var s := TradeSession.new({
		"seed": 12345, "start_date": "2014-02-03", "days": 5, "balance": 300000.0,
		"broker": {"name": "海外FX", "leverage": 888.0, "stopout": 20.0, "margin_call": 50.0, "zero_cut": true, "spread_mult": 1.5},
		"symbols": ["USDJPY", "EURJPY", "GBPJPY", "AUDJPY", "EURUSD", "EURCHF", "TRYJPY", "N225", "XAUUSD"],
		"act": 2, "goal": {"equity": 1000000.0}, "affi": true,
	}, mods)
	var ts := TradeScreen.new(s)
	add_child(ts)
	ts.session_done.connect(func(r): print("done ", r.reason, " ", r.equity))
	# 自动推进一点，让截图有内容
	for i in 40:
		s.advance()
	s.buy("USDJPY", 2.0, 0.0, 0.0)
	for i in 30:
		s.advance()
