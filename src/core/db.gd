extends Node
## 数据仓库：读取并缓存 res://data 下的 JSON。

var _cache := {}

func get_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var txt := FileAccess.get_file_as_string(path)
	if txt == "":
		push_error("DB: 读不到 %s" % path)
		return {}
	var data = JSON.parse_string(txt)
	if data == null:
		push_error("DB: JSON 解析失败 %s" % path)
		return {}
	if data is Array:
		data = {"items": data}
	_cache[path] = data
	return data

## 列出目录下所有 json（排序），用于剧情章节等可扩展内容
func list_json(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		# 导出后文件可能带 .remap/.import 后缀，这里只认 .json
		if f.ends_with(".json"):
			out.append(dir_path.path_join(f))
	out.sort()
	return out

## 按 id 取某个列表里的条目
func find(path: String, list_key: String, id: String) -> Dictionary:
	for it in get_json(path).get(list_key, []):
		if it.get("id", "") == id:
			return it
	return {}

func clear_cache() -> void:
	_cache.clear()
