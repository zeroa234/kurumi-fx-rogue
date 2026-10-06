extends Node
## 存档：局外养成、剧情进度、设置、统计、进行中的肉鸽局。

const PATH := "user://save.json"
const VERSION := 1

var data := {}

func _ready() -> void:
	load_save()

func _default() -> Dictionary:
	return {
		"version": VERSION,
		"story": {"cleared": [], "current": "", "tutorial_done": false},
		"meta": {"points": 0, "total_points": 0, "levels": {}, "unlocks": [], "ascension": 0, "max_ascension": 0},
		"stats": {"runs": 0, "clears": 0, "best_equity": 0.0, "total_trades": 0, "deaths": {}},
		"codex": {"events": [], "relics": [], "items": [], "bosses": []},
		"settings": {"speed": 1, "auto_pause_news": true, "auto_pause_indicator": true, "sfx": 0.8, "fullscreen": false, "screen_shake": true},
		"run": {},
	}

func load_save() -> void:
	data = _default()
	if not FileAccess.file_exists(PATH):
		return
	var txt := FileAccess.get_file_as_string(PATH)
	var d = JSON.parse_string(txt)
	if d is Dictionary:
		_merge(data, d)

func _merge(into: Dictionary, src: Dictionary) -> void:
	for k in src:
		if into.has(k) and into[k] is Dictionary and src[k] is Dictionary:
			_merge(into[k], src[k])
		else:
			into[k] = src[k]

func write() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data, "\t"))

func reset_all() -> void:
	data = _default()
	write()

# ---- 便捷

func story_cleared(id: String) -> bool:
	return data.story.cleared.has(id)

func mark_story(id: String) -> void:
	if not data.story.cleared.has(id):
		data.story.cleared.append(id)
	write()

func has_unlock(tag: String) -> bool:
	return tag == "" or data.meta.unlocks.has(tag)

func unlock(tag: String) -> void:
	if not data.meta.unlocks.has(tag):
		data.meta.unlocks.append(tag)

func meta_level(id: String) -> int:
	return int(data.meta.levels.get(id, 0))

func codex_add(kind: String, id: String) -> void:
	if not data.codex.has(kind):
		data.codex[kind] = []
	if not data.codex[kind].has(id):
		data.codex[kind].append(id)

func setting(key: String, default_value = null):
	return data.settings.get(key, default_value)
