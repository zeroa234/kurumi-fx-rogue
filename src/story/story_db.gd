class_name StoryDB
extends RefCounted
## 剧情章节索引：自动扫描 data/story/chapters/*.json，按 order 排序。
## 漫画更新时只需新增一个章节文件。

static var _list: Array = []

static func all() -> Array:
	if _list.is_empty():
		for p in DB.list_json("res://data/story/chapters"):
			var c := DB.get_json(p)
			if c.has("id"):
				_list.append(c)
		_list.sort_custom(func(a, b): return float(a.get("order", 0)) < float(b.get("order", 0)))
	return _list

static func chapter(id: String) -> Dictionary:
	for c in all():
		if c.id == id:
			return c
	return {}

static func next_of(id: String) -> String:
	var l := all()
	for k in l.size():
		if l[k].id == id and k + 1 < l.size():
			return l[k + 1].id
	return ""

static func is_unlocked(c: Dictionary) -> bool:
	for r in c.get("requires", []):
		if not Save.story_cleared(r):
			return false
	return true
