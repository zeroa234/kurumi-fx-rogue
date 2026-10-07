extends Node
## 背景音乐：曲目 id → assets/bgm/tracks.json 的 cues 映射到文件（多个 id 可共用一首；没映射就找 <id>.ogg），循环播放，换曲时交叉淡入淡出；没有文件就静音。
## 两层：基础曲 play()（场景/剧情决定）与临时覆盖 overlay()（商店/事件/休息、交易危机）。
## 覆盖期间基础曲暂停，clear_overlay() 后从暂停处淡入继续。曲目清单见 config/bgm-cues.json 与 docs/bgm.md。

const FADE := 1.2

var base_id := ""
var overlay_id := ""
var _base: AudioStreamPlayer = null
var _over: AudioStreamPlayer = null
var _cache := {}

func play(id: String, fade := FADE) -> void:
	if id == base_id:
		return
	var same_file := _base != null and id != "" and base_id != "" and _path(id) == _path(base_id)
	base_id = id
	if same_file: # 不同 id 共用同一首：接着放
		return
	if _base:
		_fade_out(_base, fade, true)
		_base = null
	_base = _start(id, fade)
	if _base and overlay_id != "":
		# 覆盖中：先以音量 0 暂停待命，clear_overlay() 时再从 0 淡入
		_fade_to(_base, 0.0, 0.0)
		_apply(_base, 0.0)
		_base.stream_paused = true

## 停掉一切（含覆盖曲）
func stop(fade := FADE) -> void:
	clear_overlay(fade)
	play("", fade)

func overlay(id: String, fade := FADE) -> void:
	if id == overlay_id:
		return
	overlay_id = id
	if _over:
		_fade_out(_over, fade, true)
		_over = null
	_over = _start(id, fade)
	if _base and not _base.stream_paused:
		_fade_out(_base, fade, false)

func clear_overlay(fade := FADE) -> void:
	if overlay_id == "":
		return
	overlay_id = ""
	if _over:
		_fade_out(_over, fade, true)
		_over = null
	if _base:
		_base.stream_paused = false
		_fade_to(_base, 1.0, fade)

## 设置画面调整音量后调用。
func apply_volume() -> void:
	for p in [_base, _over]:
		if p and is_instance_valid(p):
			_apply(p, float(p.get_meta("gain", 1.0)))

func volume() -> float:
	return float(Save.setting("bgm", 0.6))

func has_track(id: String) -> bool:
	return id != "" and ResourceLoader.exists(_path(id))

var _map = null

func _path(id: String) -> String:
	if _map == null:
		_map = DB.get_json("res://assets/bgm/tracks.json").get("cues", {}) if FileAccess.file_exists("res://assets/bgm/tracks.json") else {}
	return "res://assets/bgm/%s.ogg" % String(_map.get(id, id))

# ---------------------------------------------------------------- 内部

func _stream(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id]
	var s: AudioStream = null
	if has_track(id):
		s = load(_path(id))
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		_cache[id] = s # 缺文件不缓存：补进 ogg 后不用重启
	return s

func _start(id: String, fade: float) -> AudioStreamPlayer:
	var s := _stream(id)
	if s == null:
		return null
	var p := AudioStreamPlayer.new()
	p.stream = s
	add_child(p)
	_apply(p, 0.0 if fade > 0.0 else 1.0)
	p.play()
	if fade > 0.0:
		_fade_to(p, 1.0, fade)
	return p

func _apply(p: AudioStreamPlayer, gain: float) -> void:
	p.set_meta("gain", gain)
	var v := gain * volume()
	p.volume_db = linear_to_db(v) if v > 0.0001 else -80.0

func _fade_to(p: AudioStreamPlayer, to: float, dur: float) -> Tween:
	if p.has_meta("tween"):
		var old: Tween = p.get_meta("tween")
		if old and old.is_valid():
			old.kill()
	var tw := create_tween()
	tw.tween_method(func(g: float): if is_instance_valid(p): _apply(p, g), float(p.get_meta("gain", 0.0)), to, maxf(dur, 0.01))
	p.set_meta("tween", tw)
	return tw

func _fade_out(p: AudioStreamPlayer, dur: float, free_after: bool) -> void:
	var tw := _fade_to(p, 0.0, dur)
	tw.tween_callback(func():
		if not is_instance_valid(p):
			return
		if free_after:
			p.queue_free()
		else:
			p.stream_paused = true)
