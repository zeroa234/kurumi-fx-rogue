extends Node
## 加载 src/ 下所有脚本，报告编译失败的文件。

func _ready() -> void:
	var bad := 0
	for p in _scan("res://src"):
		var s = load(p)
		if s == null or not (s as Script).can_instantiate():
			printerr("COMPILE FAIL ", p)
			bad += 1
	for p in DB.list_json("res://data/story/chapters"):
		if DB.get_json(p).is_empty():
			printerr("JSON FAIL ", p)
			bad += 1
	for p in ["res://data/run/relics.json", "res://data/run/items.json", "res://data/run/friends.json", "res://data/run/nodes.json", "res://data/run/events.json", "res://data/run/meta.json", "res://data/run/brokers.json"]:
		if DB.get_json(p).is_empty():
			printerr("JSON FAIL ", p)
			bad += 1
	print("compile check: %d failures" % bad)
	get_tree().quit(1 if bad > 0 else 0)

func _scan(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	for f in d.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		out.append_array(_scan(dir.path_join(sub)))
	return out
