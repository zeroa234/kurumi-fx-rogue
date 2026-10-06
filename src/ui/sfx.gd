extends Node
## 简易音效：优先播放 assets/sfx/<name>.wav，没有就静音。

var _players: Array[AudioStreamPlayer] = []
var _cache := {}

func _ready() -> void:
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

func play(sfx_name: String, pitch := 1.0) -> void:
	var vol: float = float(Save.setting("sfx", 0.8))
	if vol <= 0.0:
		return
	var stream: AudioStream = _cache.get(sfx_name)
	if stream == null:
		var path := "res://assets/sfx/%s.wav" % sfx_name
		if not ResourceLoader.exists(path):
			return
		stream = load(path)
		_cache[sfx_name] = stream
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch
			p.volume_db = linear_to_db(vol)
			p.play()
			return
