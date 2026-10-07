extends Node
## BGM 自检：config 里每个曲目 id 都能找到并加载成循环 OGG；章节里用到的 bgm 都在清单里；play/overlay/clear 的状态切换。
## 不写存档。→ "BGM CHECK: 0 failures"

var fails := 0

func _fail(msg: String) -> void:
	fails += 1
	print("FAIL ", msg)

func _ready() -> void:
	var cues: Dictionary = DB.get_json("res://assets/bgm/tracks.json").get("cues", {})
	if cues.is_empty():
		_fail("tracks.json 没有 cues")
	for id in cues:
		if not Bgm.has_track(id):
			_fail("缺文件 %s → %s" % [id, Bgm._path(id)])
			continue
		var s = Bgm._stream(id)
		if not (s is AudioStreamOggVorbis and (s as AudioStreamOggVorbis).loop):
			_fail("不是循环 OGG：%s" % id)
	# 章节与代码里引用的 id 必须都在清单里
	for f in DirAccess.get_files_at("res://data/story/chapters"):
		if not f.ends_with(".json"):
			continue
		var ch := DB.get_json("res://data/story/chapters/" + f)
		for s in ch.get("scenes", []):
			for k in ["bgm", "bgm_danger", "bgm_peg_break"]:
				var v := String(s.get(k, ""))
				if v != "" and not cues.has(v):
					_fail("%s 场景字段 %s=%s 不在 tracks.json" % [f, k, v])
	for id in ["title", "menu", "map", "event", "shop", "rest", "trade_main", "trade_elite", "boss", "boss_final", "snb_shock", "trade_danger", "victory", "gameover"]:
		if not cues.has(id):
			_fail("代码用到的 %s 不在 tracks.json" % id)
	# 状态切换
	Bgm.play("title", 0.0)
	_expect(Bgm._base != null and Bgm._base.playing and not Bgm._base.stream_paused, "play 后基础曲在播")
	Bgm.overlay("shop", 0.0)
	await get_tree().create_timer(0.5).timeout
	_expect(Bgm._over != null and Bgm._over.playing, "overlay 在播")
	_expect(Bgm._base.stream_paused, "overlay 时基础曲暂停")
	Bgm.play("map", 0.0) # 覆盖中换基础曲
	_expect(Bgm._base.stream_paused and float(Bgm._base.get_meta("gain")) == 0.0, "覆盖中换的基础曲音量 0 暂停")
	Bgm.clear_overlay(0.0)
	await get_tree().create_timer(0.5).timeout
	_expect(Bgm.overlay_id == "" and not Bgm._base.stream_paused, "clear_overlay 后基础曲恢复")
	var p := Bgm._base
	Bgm.play("story_ominous", 0.0)
	Bgm.play("replay_2008", 0.0) # 同一文件
	_expect(Bgm._base != p and Bgm.base_id == "replay_2008", "换 id 记录正确")
	var q := Bgm._base
	Bgm.play("story_ominous", 0.0)
	_expect(Bgm._base == q, "共用文件的 id 之间切换不重启")
	Bgm.overlay("trade_danger", 0.0)
	Bgm.stop(0.0)
	_expect(Bgm.overlay_id == "" and Bgm.base_id == "", "stop 清空基础曲与覆盖")
	print("BGM CHECK: %d failures" % fails)
	get_tree().quit()

func _expect(cond: bool, what: String) -> void:
	if not cond:
		_fail(what)
