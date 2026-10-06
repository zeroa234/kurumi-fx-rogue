extends Node
## 肉鸽存档往返：RunState → JSON → RunState，关键字段一致。

func _ready() -> void:
	Save.data = Save._default()
	Save.unlock("friend_mochiko")
	var r := RunState.create({"broker": "domestic", "friends": ["mochiko"], "seed": 99})
	var first: String = r.available()[0]
	r.enter(first)
	r.add_relic("anchor")
	r.add_item("energy_drink")
	r.add_curse("guilt")
	r.debt = 123456.0
	r.fp = 77
	r.complete_current()
	var txt := JSON.stringify(r.to_dict())
	var r2 := RunState.from_dict(JSON.parse_string(txt))
	var ok := true
	for k in ["act", "layer", "current", "money", "debt", "fp", "broker_id", "relics", "items", "curses", "friends"]:
		var a = r.get(k)
		var b = r2.get(k)
		if str(a) != str(b):
			printerr("MISMATCH ", k, " ", a, " vs ", b)
			ok = false
	if r2.available() != r.available():
		printerr("MISMATCH available ", r.available(), " vs ", r2.available())
		ok = false
	if absf(r2.mods.get_v("sl_slip_mult") - r.mods.get_v("sl_slip_mult")) > 1e-6:
		printerr("MISMATCH mods")
		ok = false
	var cfg := r2.trade_config(r2.node(r2.available()[0]))
	print("next node cfg ok: ", cfg.start_date, " days ", cfg.days, " balance ", cfg.balance)
	print("SAVE ROUNDTRIP ", "OK" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
