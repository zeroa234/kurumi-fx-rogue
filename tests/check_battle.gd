extends Node
## 实跑剧情战役的交易场景（无界面），打印关键结果。-- --chapter=ch11

func _ready() -> void:
	var ch := "ch11"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--chapter="): ch = a.substr(10)
	var c := StoryDB.chapter(ch)
	for s in c.scenes:
		if s.type != "trade":
			continue
		var mods := Mods.new()
		mods.set_layer("scene", s.get("mods", {}))
		var sess := TradeSession.new(s.config.duplicate(true), mods)
		for p in s.get("positions", []):
			var r = sess.account.open_position(p.symbol, int(p.side), float(p.lots), float(p.get("sl", 0.0)), float(p.get("tp", 0.0)))
			if r is Account.Position and p.has("entry"):
				(r as Account.Position).entry = float(p.entry)
			elif r is String:
				print("  预置持仓失败：", r)
		var sym: String = s.config.symbols[0]
		var ins := sess.market.get_ins(sym)
		print("%s 开始 %s 净值 %s 维持率 %.0f%% %s=%s" % [ch, sess.now_text(), GameDate.yen(sess.account.equity()), sess.account.margin_level(), sym, sess.market.format_price(ins, ins.mid)])
		var low := INF
		var n := 0
		while not sess.done and n < 5000:
			sess.advance()
			n += 1
			low = minf(low, ins.l[ins.l.size() - 1])
			if n % 24 == 0 or (sess.account.debt > 0.0 and n % 4 == 0 and n < 400):
				pass
		print("  结束 %s 原因 %s  最低 %s 收盘 %s" % [sess.now_text(), sess.result.reason, sess.market.format_price(ins, low), sess.market.format_price(ins, ins.mid)])
		print("  余额 %s 不足金 %s 强平次数 %d" % [GameDate.yen(sess.account.balance), GameDate.yen(sess.account.debt), int(sess.account.stats.stopouts)])
	get_tree().quit()
